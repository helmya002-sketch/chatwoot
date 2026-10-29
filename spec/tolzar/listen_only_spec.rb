require 'rails_helper'

# Tolzar listen-only WhatsApp inboxes (Tolzar::ListenOnly): our own Meta app next to another
# provider on the same number. Nothing may reach the customer and nothing about the number may change.
RSpec.describe Tolzar::ListenOnly do
  let(:account) { create(:account) }
  let(:config) do
    { 'api_key' => 'our-app-token', 'app_secret' => 'our-app-secret', 'phone_number_id' => '111',
      'business_account_id' => 'waba-1', 'webhook_verify_token' => 'vt',
      'source' => Tolzar::ListenOnly::SOURCE, Tolzar::ListenOnly::KEY => true }
  end
  # The factory merges its own ids over provider_config on create, so set ours afterwards.
  def listen_only_channel(phone, cfg)
    ch = create(:channel_whatsapp, account: account, phone_number: phone, provider: 'whatsapp_cloud',
                                   provider_config: cfg, sync_templates: false, validate_provider_config: false)
    ch.update_columns(provider_config: cfg)
    ch.reload
  end

  let(:channel) { listen_only_channel('+201000000001', config) }
  let(:inbox) { channel.inbox || create(:inbox, account: account, channel: channel) }

  # WebMock blocks every request a test does not stub, so an unexpected graph.facebook.com call fails it.

  it 'flags only channels that carry the listen-only key' do
    expect(described_class.channel?(channel)).to be(true)
    other = create(:channel_whatsapp, account: account, phone_number: '+201000000002', provider: 'whatsapp_cloud',
                                      sync_templates: false, validate_provider_config: false)
    expect(described_class.channel?(other)).to be(false)
    expect(described_class.channel?(nil)).to be(false)
  end

  describe 'nothing reaches the customer' do
    it 'never runs the WhatsApp send service for a reply' do
      conversation = create(:conversation, account: account, inbox: inbox)
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      expect(Whatsapp::SendOnWhatsappService).not_to receive(:new)
      SendReplyJob.perform_now(message.id)
    end

    it 'refuses sends, templates, CSAT templates and calling settings at the provider, without an HTTP call' do
      provider = Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel)
      message = build(:message, content: 'hello')
      expect(provider.send_message('+201000000009', message)).to be_nil
      expect(provider.send_template('+201000000009', { name: 't', lang_code: 'en', parameters: [] }, message)).to be_nil
      expect(provider.create_csat_template({})).to be_nil
      expect(provider.delete_csat_template('t')).to be_nil
      expect(a_request(:any, /graph.facebook.com/)).not_to have_been_made
    end

    it 'refuses a contact-info request' do
      result = Whatsapp::Providers::WhatsappCloudContactInfoRequestService.perform(channel, '+201000000009',
                                                                                    build(:message, content: 'x'))
      expect(result).to be_nil
      expect(a_request(:any, /graph.facebook.com/)).not_to have_been_made
    end

    it 'cannot turn calling on or off at Meta' do
      expect { channel.enable_voice_calling! }.to raise_error(/listen-only/)
      expect { channel.disable_voice_calling! }.to raise_error(/listen-only/)
    end
  end

  describe 'the number is never touched' do
    it 'connect subscribes our app to the WABA and does nothing else (no /register, no phone override)' do
      subscribe = stub_request(:post, %r{graph.facebook.com/.*/waba-1/subscribed_apps}).to_return(status: 200, body: '{"success":true}')
      Whatsapp::WebhookSetupService.new(channel, 'waba-1', 'our-app-token').perform
      expect(subscribe).to have_been_made.once
      expect(a_request(:post, %r{graph.facebook.com/.*/111(/register)?$})).not_to have_been_made
    end

    it 're-registering the callback is the same single WABA subscription' do
      subscribe = stub_request(:post, %r{/waba-1/subscribed_apps}).to_return(status: 200, body: '{"success":true}')
      Whatsapp::WebhookSetupService.new(channel).register_callback
      expect(subscribe).to have_been_made.once
      expect(a_request(:post, %r{graph.facebook.com/.*/111$})).not_to have_been_made
    end

    it 'delete removes only our app subscription, never the phone override or the registration' do
      unsubscribe = stub_request(:delete, %r{/waba-1/subscribed_apps}).to_return(status: 200, body: '{"success":true}')
      Whatsapp::WebhookTeardownService.new(channel).perform
      expect(unsubscribe).to have_been_made.once
      expect(a_request(:post, /graph.facebook.com/)).not_to have_been_made
    end

    it 'keeps our subscription while another inbox still uses the WABA' do
      listen_only_channel('+201000000003', config.merge('phone_number_id' => '222'))
      Whatsapp::WebhookTeardownService.new(channel).perform
      expect(a_request(:any, /graph.facebook.com/)).not_to have_been_made
    end
  end

  describe Tolzar::WhatsappListenOnlySetupService do
    let(:validation) { instance_double(Whatsapp::ManualSetupValidationService) }

    before do
      allow(Whatsapp::ManualSetupValidationService).to receive(:new).and_return(validation)
      allow(validation).to receive(:perform).and_return(
        { display_phone_number: '+201000000005', phone_number_id: '555', waba_id: 'waba-9', suggested_inbox_name: 'DWT' }
      )
      stub_request(:post, %r{/waba-9/subscribed_apps}).to_return(status: 200, body: '{"success":true}')
      # Creating the channel reads Meta (token check, phone id check, template sync): GET only.
      json = { 'Content-Type' => 'application/json' }
      stub_request(:get, %r{graph.facebook.com/.*/waba-9/message_templates}).to_return(status: 200, body: '{"data":[]}', headers: json)
      stub_request(:get, %r{graph.facebook.com/.*/waba-9/phone_numbers}).to_return(status: 200, body: '{"data":[{"id":"555"}]}',
                                                                                    headers: json)
    end

    it 'creates a flagged inbox with every customer-facing auto-message off and subscribes only our app' do
      setup = described_class.new(account: account, waba_id: 'waba-9', phone_number_id: '555',
                                  access_token: 'tok', app_secret: 'sec').perform
      expect(Tolzar::ListenOnly.channel?(setup.channel)).to be(true)
      expect(setup.channel.provider_config).to include('app_secret' => 'sec', 'source' => 'tolzar_listen_only')
      expect(setup.inbox).to have_attributes(greeting_enabled: false, working_hours_enabled: false,
                                             csat_survey_enabled: false, enable_email_collect: false)
      expect(setup.webhook_error).to be_nil
      expect(a_request(:post, /register/)).not_to have_been_made
      expect(a_request(:post, %r{graph.facebook.com/.*/555$})).not_to have_been_made     # no phone-level override
    end

    it 'needs the app secret (Meta signs every webhook with it)' do
      expect do
        described_class.new(account: account, waba_id: 'waba-9', phone_number_id: '555', access_token: 'tok', app_secret: '').perform
      end.to raise_error(ArgumentError, /app secret/)
    end
  end
end
