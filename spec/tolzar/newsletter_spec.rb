require 'rails_helper'

# Tolzar: the newsletter to the app's own users (owner decision 30 Oct 2026). Who gets it, the RFC 8058
# one-click unsubscribe, Postal's bounce events, the warm-up batches, and the super admin page.
RSpec.describe 'Tolzar newsletter', type: :request do
  let(:account) { create(:account) }
  let!(:reader) { create(:user, account: account) }
  let(:env) do
    { NEWSLETTER_FROM: 'Adam from Tolzar <news@news.example.test>', NEWSLETTER_SMTP_DOMAIN: 'news.example.test',
      NEWSLETTER_POSTAL_ADDRESS: 'Example Street 1, Hurghada', NEWSLETTER_PRIVACY_URL: 'https://example.test/privacy',
      FRONTEND_URL: 'https://app.example.test' }
  end
  let(:newsletter) { Tolzar::Newsletter.create!(subject: 'October news', body_markdown: "# Hello\n\nNew: **reports**.<script>x()</script>") }

  around { |example| with_modified_env(env) { example.run } }

  describe 'audience' do
    it 'is the confirmed users with a workspace, minus opt-outs and suppressions' do
      opted_out = create(:user, account: account)
      bounced = create(:user, account: account)
      no_workspace = create(:user)
      Tolzar::NewsletterRecipient.opt_out!(opted_out.id)
      Tolzar::NewsletterRecipient.suppress!(bounced.id, 'hard_bounce')

      ids = Tolzar::NewsletterAudience.new.users.map(&:id)
      expect(ids).to include(reader.id)
      expect(ids).not_to include(opted_out.id, bounced.id, no_workspace.id)
    end

    it 'filters by the user language, then the workspace language' do
      account.update!(locale: 'de')
      arabic = create(:user, account: account)
      arabic.update!(ui_settings: { 'locale' => 'ar' })

      expect(Tolzar::NewsletterAudience.new(locale: 'ar').users.map(&:id)).to eq([arabic.id])
      expect(Tolzar::NewsletterAudience.new(locale: 'de').users.map(&:id)).to eq([reader.id])
    end
  end

  describe 'one-click unsubscribe' do
    let(:token) { Tolzar::NewsletterToken.for(reader.id) }

    it 'shows a button on GET and does not unsubscribe (mail scanners follow links)' do
      get "/tolzar/newsletter/unsubscribe/#{token}"
      expect(response).to have_http_status(:ok)
      expect(Tolzar::NewsletterRecipient.find_by(user_id: reader.id)).to be_nil
    end

    it 'unsubscribes on the mailbox provider one-click POST, without a CSRF token, and stays idempotent' do
      2.times { post "/tolzar/newsletter/unsubscribe/#{token}", params: 'List-Unsubscribe=One-Click' }
      expect(response).to have_http_status(:ok)
      first = Tolzar::NewsletterRecipient.find_by(user_id: reader.id).opted_out_at
      expect(first).to be_present
      expect(Tolzar::NewsletterAudience.new.users.map(&:id)).not_to include(reader.id)
    end

    it 'refuses a forged or tampered token' do
      post "/tolzar/newsletter/unsubscribe/#{token}x"
      expect(response).to have_http_status(:not_found)
      get "/tolzar/newsletter/unsubscribe/#{Rails.application.message_verifier(:other).generate(reader.id)}"
      expect(response).to have_http_status(:not_found)
      expect(Tolzar::NewsletterRecipient.count).to eq(0)
    end
  end

  describe 'the message' do
    let(:delivery) do
      Tolzar::NewsletterDelivery.create!(newsletter: newsletter, user: reader, email: reader.email,
                                         message_id: 'tolzar-nl-1-abc@news.example.test')
    end
    let(:mail) { Tolzar::NewsletterMailer.issue(delivery) }

    it 'carries the RFC 8058 headers, our Message-ID and both parts' do
      expect(mail['List-Unsubscribe'].value).to start_with('<https://app.example.test/tolzar/newsletter/unsubscribe/')
      expect(mail['List-Unsubscribe-Post'].value).to eq('List-Unsubscribe=One-Click')
      expect(mail.message_id).to eq('tolzar-nl-1-abc@news.example.test')
      expect(mail.from).to eq(['news@news.example.test'])
      expect(mail.text_part.body.decoded).to include('Example Street 1, Hurghada')
    end

    it 'writes the footer in the reader language (es, pt-PT among the site languages)' do
      reader.update!(ui_settings: { 'locale' => 'es' })
      expect(mail.text_part.body.decoded).to include('Darse de baja')
      reader.update!(ui_settings: { 'locale' => 'pt' })
      expect(Tolzar::NewsletterMailer.issue(delivery.reload).text_part.body.decoded).to include('Cancelar a subscrição')
    end

    it 'renders the Markdown, escapes pasted HTML and adds no tracking' do
      html = mail.html_part.body.decoded
      expect(html).to include('<strong>reports</strong>')
      expect(html).not_to include('<script>')
      expect(html).not_to match(/<img[^>]+(width="1"|height="1")/)
      expect(html).to include('https://example.test/privacy')
    end
  end

  describe 'Postal bounce webhook' do
    let(:key) { OpenSSL::PKey::RSA.new(2048) }
    let(:delivery) do
      Tolzar::NewsletterDelivery.create!(newsletter: newsletter, user: reader, email: reader.email, status: 'sent',
                                         message_id: 'tolzar-nl-9-x@news.example.test')
    end
    let(:hook_env) { env.merge(NEWSLETTER_WEBHOOK_TOKEN: 'a' * 32, NEWSLETTER_POSTAL_WEBHOOK_KEY: key.public_key.to_pem) }

    def deliver_event(body, token: 'a' * 32, signer: key)
      signature = Base64.strict_encode64(signer.sign(OpenSSL::Digest.new('SHA256'), body))
      post "/tolzar/newsletter/postal/#{token}", params: body,
                                                  headers: { 'Content-Type' => 'application/json', 'X-Postal-Signature-256' => signature }
    end

    it 'suppresses the user on a hard bounce' do
      body = { event: 'MessageBounced', payload: { original_message: { message_id: "<#{delivery.message_id}>" } } }.to_json
      with_modified_env(hook_env) { deliver_event(body) }
      expect(response).to have_http_status(:ok)
      expect(delivery.reload.status).to eq('bounced')
      expect(Tolzar::NewsletterRecipient.find_by(user_id: reader.id).suppression_reason).to eq('hard_bounce')
    end

    it 'pauses the user on the second soft bounce within 30 days' do
      body = { event: 'MessageDeliveryFailed', payload: { status: 'SoftFail', message: { message_id: delivery.message_id } } }.to_json
      with_modified_env(hook_env) { deliver_event(body) }
      expect(Tolzar::NewsletterRecipient.find_by(user_id: reader.id).suppressed_at).to be_nil
      with_modified_env(hook_env) { deliver_event(body) }
      expect(Tolzar::NewsletterRecipient.find_by(user_id: reader.id).suppression_reason).to eq('soft_bounces')
    end

    it 'refuses a wrong path token or a bad signature before reading anything' do
      body = { event: 'MessageBounced', payload: { original_message: { message_id: delivery.message_id } } }.to_json
      with_modified_env(hook_env) { deliver_event(body, token: 'b' * 32) }
      expect(response).to have_http_status(:not_found)
      with_modified_env(hook_env) { deliver_event(body, signer: OpenSSL::PKey::RSA.new(2048)) }
      expect(response).to have_http_status(:forbidden)
      expect(Tolzar::NewsletterRecipient.count).to eq(0)
    end
  end

  describe 'sending' do
    include ActiveJob::TestHelper

    it 'is refused while NEWSLETTER_ENABLED is not true' do
      expect { Tolzar::NewsletterSendJob.perform_now(newsletter.id) }.to raise_error(RuntimeError, /NEWSLETTER_ENABLED/)
      expect(newsletter.reload.status).to eq('draft')
    end

    it 'queues each user once, sends within the daily cap and skips a user who opted out meanwhile' do
      second = create(:user, account: account)
      third = create(:user, account: account)
      with_modified_env(env.merge(NEWSLETTER_ENABLED: 'true', NEWSLETTER_DAILY_CAP: '2', NEWSLETTER_BATCH_SIZE: '50')) do
        Tolzar::NewsletterSendJob.new.perform(newsletter.id)
        expect(newsletter.reload.recipients_count).to eq(3)
        Tolzar::NewsletterRecipient.opt_out!(second.id)

        expect { Tolzar::NewsletterBatchJob.new.perform(newsletter.id) }.to change(ActionMailer::Base.deliveries, :count).by(1)
        expect(newsletter.counts).to include('sent' => 1, 'skipped' => 1, 'queued' => 1)
        expect(ActionMailer::Base.deliveries.last.to).to eq([reader.email])
        expect(Tolzar::NewsletterDelivery.find_by(user_id: third.id).status).to eq('queued') # waits for the next day's room
      end
    end
  end

  describe 'super admin page' do
    let(:super_admin) { create(:super_admin) }

    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows the page with the audience and a preview of a draft' do
      get "/super_admin/newsletter?id=#{newsletter.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('October news').and include('srcdoc=')
    end

    it 'saves a draft and refuses to send without NEWSLETTER_ENABLED or the typed confirmation' do
      post '/super_admin/newsletter', params: { newsletter: { subject: 'Hi', body_markdown: 'Body', locale: '' } }
      draft = Tolzar::Newsletter.last
      expect(draft.locale).to be_nil

      post "/super_admin/newsletter/deliver?id=#{draft.id}", params: { confirm: 'SEND' }
      expect(flash[:alert]).to be_present
      with_modified_env(env.merge(NEWSLETTER_ENABLED: 'true')) do
        post "/super_admin/newsletter/deliver?id=#{draft.id}", params: { confirm: 'send' }
        expect(flash[:alert]).to be_present
        expect { post "/super_admin/newsletter/deliver?id=#{draft.id}", params: { confirm: 'SEND' } }
          .to have_enqueued_job(Tolzar::NewsletterSendJob).with(draft.id)
      end
    end

    it 'suppresses a complaint by email but cannot remove a user opt-out' do
      Tolzar::NewsletterRecipient.opt_out!(reader.id)
      post '/super_admin/newsletter/suppression', params: { email: reader.email, op: 'suppress', reason: 'complaint' }
      post '/super_admin/newsletter/suppression', params: { email: reader.email, op: 'unsuppress' }
      rec = Tolzar::NewsletterRecipient.find_by(user_id: reader.id)
      expect(rec.suppressed_at).to be_nil
      expect(rec.opted_out_at).to be_present
    end
  end
end
