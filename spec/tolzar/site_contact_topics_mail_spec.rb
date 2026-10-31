require 'rails_helper'

# Site v3 (launch lane, 31 Oct): two more topics with a label each, and the trial requester's instant
# "what happens next" mail (off unless TOLZAR_TRIAL_MAIL_FROM is set; once per address a day; fixed text).
RSpec.describe 'Tolzar site contact: topics and the trial mail', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:env) { { TOLZAR_CONTACT_INBOX_ID: inbox.id.to_s, TOLZAR_CONTACT_ORIGINS: 'https://tolzar.com' } }
  let(:form) { { name: 'Mona Adel <b>', email: 'mona@example.com', topic: 'trial', message: 'Call me <script>x</script>' } }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Redis::Alfred.delete('tolzar:site_contact:ip:127.0.0.1')
    Redis::Alfred.delete("tolzar:site_contact:day:#{Time.current.utc.to_date}")
    Redis::Alfred.delete("tolzar:trial_mail:#{Digest::SHA256.hexdigest('mona@example.com')}:#{Time.current.utc.to_date}")
    ActionMailer::Base.deliveries.clear
  end

  it 'accepts the setup and calculator topics and labels every conversation site-<topic>' do
    post '/tolzar/site/contact', params: form.merge(topic: 'setup')
    post '/tolzar/site/contact', params: form.merge(topic: 'calculator', message: 'Result: 120 h saved / month')
    post '/tolzar/site/contact', params: form.merge(topic: 'nonsense')
    convs = inbox.conversations.order(:id).last(3)
    expect(convs.map { |c| c.additional_attributes['topic'] }).to eq(%w[setup calculator contact])
    expect(convs.map(&:label_list)).to eq([['site-setup'], ['site-calculator'], ['site-contact']])
    expect(convs[1].messages.last.content).to include('Result: 120 h saved / month')
  end

  it 'sends no mail while TOLZAR_TRIAL_MAIL_FROM is unset' do
    expect { post '/tolzar/site/contact', params: form }.not_to have_enqueued_mail(Tolzar::TrialMailer, :confirmation)
  end

  it 'queues one trial mail for the typed address only, once a day, only for a trial' do
    with_modified_env(TOLZAR_TRIAL_MAIL_FROM: 'Tolzar <noreply@tolzar.com>') do
      expect { post '/tolzar/site/contact', params: form.merge(lang: 'de') }
        .to have_enqueued_mail(Tolzar::TrialMailer, :confirmation).with('mona@example.com', 'Mona', 'de')
      expect { post '/tolzar/site/contact', params: form }.not_to have_enqueued_mail(Tolzar::TrialMailer, :confirmation)
      expect { post '/tolzar/site/contact', params: form.merge(topic: 'contact', email: 'other@example.com') }
        .not_to have_enqueued_mail(Tolzar::TrialMailer, :confirmation)
    end
  end

  it 'renders the fixed trial text and delivers it, nothing typed echoed but the first name' do
    with_modified_env(TOLZAR_TRIAL_MAIL_FROM: 'Adam from Tolzar <noreply@tolzar.com>') do
      mail = Tolzar::TrialMailer.confirmation('mona@example.com', 'Mona', 'de')
      expect { mail.deliver_now }.to change(ActionMailer::Base.deliveries, :size).by(1)
      expect(mail.to).to eq(['mona@example.com'])
      expect(mail[:from].display_names).to eq(['Adam from Tolzar'])
      expect(mail.subject).to eq('Ihre Tolzar-Testphase: so geht es weiter')
      expect(mail.text_part.body.to_s).to include('Hallo Mona,', 'Innerhalb von 1 Werktag', 'Adam von Tolzar')
      expect(mail.html_part.body.to_s).not_to include('<script>')
    end
  end

  it 'folds the v3 extras of a plain (no-JS) post into the message, once' do
    post '/tolzar/site/contact', params: form.merge(business_type: 'Online shop', channels: %w[WhatsApp Instagram],
                                                    monthly: 'Under 500', pref_lang: 'Arabic', describe: 'We sell bikes.')
    text = inbox.conversations.last.messages.last.content
    expect(text).to include('Business type: Online shop', 'Channels: WhatsApp, Instagram', 'Monthly messages: Under 500',
                            'Preferred language: Arabic', 'In their words: We sell bikes.')

    post '/tolzar/site/contact', params: form.merge(business_type: 'Online shop', message: "Hi
Business type: Online shop")
    expect(inbox.conversations.last.messages.last.content.scan('Business type:').size).to eq(1)
  end
end
