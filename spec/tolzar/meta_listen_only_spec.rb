require 'rails_helper'

# A workspace's own Meta app (Tolzar::MetaApp) with listen-only Facebook Page / Instagram inboxes:
# Meta's webhook is verified with THAT app's secret, events reach only this workspace's listen-only
# pages, nothing is ever sent, and comments arrive as their own conversations.
# WebMock refuses every request a test does not stub, so an unexpected Graph call fails it.
RSpec.describe 'Tolzar Meta app, listen-only Facebook and Instagram' do
  let(:account) { create(:account) }
  let(:secret) { 'a' * 32 }
  let!(:meta_app) { Tolzar::MetaApp.create!(account: account, app_id: '1234567890123', app_secret: secret) }
  let(:channel) do
    Channel::FacebookPage.create!(account: account, page_id: '1001', page_access_token: 'page-token',
                                  user_access_token: 'system-user-token', instagram_id: '1784', tolzar_listen_only: true)
  end
  let!(:inbox) { create(:inbox, account: account, channel: channel) }

  def sign(body)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  describe Tolzar::MetaApp do
    it 'makes its own tokens and checks Meta signatures with its own secret only' do
      expect(meta_app.webhook_token).to match(/\A\h{32}\z/)
      expect(meta_app.verify_token).to match(/\A\h{32}\z/)
      expect(meta_app.valid_signature?('{"a":1}', sign('{"a":1}'))).to be(true)
      expect(meta_app.valid_signature?('{"a":1}', sign('{"a":2}'))).to be(false)
      expect(meta_app.valid_signature?('{"a":1}', nil)).to be(false)
      expect(meta_app.view.keys).not_to include(:app_secret, :verify_token)
    end

    it 'refuses a malformed app id or secret' do
      bad = described_class.new(account: create(:account), app_id: 'abc', app_secret: 'short')
      expect(bad).not_to be_valid
      expect(bad.errors.attribute_names).to include(:app_id, :app_secret)
    end
  end

  describe 'webhook', type: :request do
    let(:url) { "/tolzar/meta/hook/#{meta_app.webhook_token}" }

    it 'answers the verify handshake only with the right token' do
      get url, params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => meta_app.verify_token, 'hub.challenge' => '42' }
      expect(response.body).to eq('42')
      get url, params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => 'wrong', 'hub.challenge' => '42' }
      expect(response).to have_http_status(:not_found)
      get "/tolzar/meta/hook/#{'b' * 32}", params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => meta_app.verify_token }
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a body not signed with this app secret' do
      body = { object: 'page', entry: [] }.to_json
      post url, params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => 'sha256=00' }
      expect(response).to have_http_status(:forbidden)
    end

    it 'queues Messenger events (messaging and standby) for this workspace listen-only page only' do
      body = { object: 'page', entry: [
        { id: '1001', messaging: [{ sender: { id: 'u1' }, recipient: { id: '1001' }, message: { mid: 'm1', text: 'hi' } }],
          standby: [{ sender: { id: 'u2' }, recipient: { id: '1001' }, message: { mid: 'm2', text: 'yo' } }] },
        { id: '9999', messaging: [{ sender: { id: 'u3' }, recipient: { id: '9999' }, message: { mid: 'm3' } }] }
      ] }.to_json
      expect do
        post url, params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => sign(body) }
      end.to have_enqueued_job(Webhooks::FacebookEventsJob).exactly(2).times
      expect(response).to have_http_status(:ok)
    end
  end

  describe Tolzar::MetaListenOnlySetupService do
    let(:other) { create(:account) }

    before { Tolzar::MetaApp.create!(account: other, app_id: '2234567890123', app_secret: 'b' * 32) }

    it 'reads the page once, creates a quiet inbox and subscribes only our app' do
      read = stub_request(:get, %r{graph\.facebook\.com/v26\.0/2002002\?})
             .to_return(body: { id: '2002002', name: 'Shop', access_token: 'pt',
                                instagram_business_account: { id: '1785' } }.to_json)
      sub = stub_request(:post, %r{graph\.facebook\.com/v26\.0/2002002/subscribed_apps\?.*subscribed_fields=messages%2Cmessage_echoes})
            .to_return(body: { success: true }.to_json)
      setup = described_class.new(account: other, page_id: '2002002', access_token: 'sut').perform
      expect(read).to have_been_requested.once
      expect(sub).to have_been_requested.once
      expect(setup.channel).to have_attributes(tolzar_listen_only: true, instagram_id: '1785', page_access_token: 'pt')
      expect(setup.inbox).to have_attributes(greeting_enabled: false, csat_survey_enabled: false)
      expect(setup.webhook_error).to be_nil
    end

    it 'needs the workspace app first' do
      expect { described_class.new(account: create(:account), page_id: '2002002', access_token: 't').perform }
        .to raise_error(ArgumentError, /Meta app/)
    end
  end

  it 'sends nothing from a listen-only page inbox' do
    contact = create(:contact, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'psid-1')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                               content: 'hello')
    allow(Facebook::Messenger::Bot).to receive(:deliver)
    Facebook::SendOnFacebookService.new(message: message).perform
    expect(Facebook::Messenger::Bot).not_to have_received(:deliver)
    expect(Tolzar::ListenOnly.inbox?(inbox)).to be(true)
  end

  describe Tolzar::MetaCommentIngestService do
    def ingest(value, platform = 'facebook')
      described_class.new(channel: channel, platform: platform, value: value).perform
    end

    let(:comment) do
      { item: 'comment', verb: 'add', comment_id: '1001_c1', post_id: '1001_p1', parent_id: '1001_p1',
        message: 'How much is it?', from: { id: 'fan-1', name: 'Fan One' } }
    end

    it 'makes one comment conversation per commenter and post, apart from DMs' do
      ingest(comment)
      ingest(comment.merge(comment_id: '1001_c2', message: 'And delivery?'))
      conversation = inbox.conversations.sole
      expect(conversation.additional_attributes['tolzar_comment']).to include('platform' => 'facebook', 'post_id' => '1001_p1')
      expect(conversation.label_list).to include('comment')
      expect(conversation.messages.incoming.pluck(:content)).to eq(['How much is it?', 'And delivery?'])
      expect(conversation.contact_inbox.source_id).to eq('comment:facebook:fan-1')
      ingest(comment) # a repeated webhook adds nothing
      expect(conversation.messages.incoming.count).to eq(2)
    end

    it 'shows the page reply in the thread, then edits and removals' do
      ingest(comment)
      ingest(comment.merge(comment_id: '1001_r1', parent_id: '1001_c1', message: 'It is 20 EUR', from: { id: '1001', name: 'Shop' }))
      conversation = inbox.conversations.sole
      expect(conversation.messages.outgoing.pluck(:content)).to eq(['It is 20 EUR'])
      ingest(comment.merge(verb: 'edited', message: 'How much is it, please?'))
      expect(conversation.messages.incoming.first.content).to eq('How much is it, please?')
      ingest(comment.merge(verb: 'remove'))
      expect(conversation.messages.activity.last.content).to eq('Comment removed on Facebook')
    end

    it 'reads Instagram comments too' do
      ingest({ id: 'ig-c1', text: 'Love it', from: { id: 'igu-1', username: 'fan' }, media: { id: 'ig-m1' } }, 'instagram')
      expect(inbox.conversations.sole.additional_attributes.dig('tolzar_comment', 'post_id')).to eq('ig-m1')
    end
  end

  describe 'settings API', type: :request do
    let!(:owner) { create(:user, account: account, role: :administrator) }
    let!(:manager) { create(:user, account: account, role: :administrator) }
    let(:base) { "/api/v1/accounts/#{account.id}/tolzar/meta_app" }

    # A Manager's role is looked up in the brain (Tolzar roles); no brain in tests.
    before do
      allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'roles' => {} })
    end

    it 'shows the app without its secret, and only the Owner changes it' do
      get base, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get base, headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body['app']).to include('app_id' => '1234567890123', 'secret_last4' => 'aaaa')
      expect(response.body).not_to include(secret)
      expect(response.parsed_body['pages'].pluck('page_id')).to eq(['1001'])
      post base, params: { app_id: '1234567890124' }, headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body).not_to have_key('verify_token') # only on create
      expect(meta_app.reload.app_secret).to eq(secret)
    end
  end
end
