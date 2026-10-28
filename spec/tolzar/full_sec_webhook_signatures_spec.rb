require 'rails_helper'

# M5 (full-sec review 2026-10-29): Chatwoot core's Twilio, SMS (Bandwidth) and Telegram webhooks are
# verified for a known channel; a missing or wrong signature/token is refused with 403. A request that
# names no known channel goes on as before (its job finds nothing).

RSpec.describe 'Tolzar M5: Twilio webhook signatures', type: :request do
  include Rails.application.routes.url_helpers

  # Twilio's documented scheme: Base64(HMAC-SHA1(auth token, URL + each POST param name+value, sorted by name)).
  def tolzar_twilio_signature(token, url, params)
    data = url + params.sort.map { |k, v| "#{k}#{v}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest('sha1', token, data))
  end

  let(:channel) { create(:channel_twilio_sms, :with_phone_number) }
  let(:inbound) do
    { 'From' => '+15550001111', 'To' => channel.phone_number, 'Body' => 'hi', 'AccountSid' => channel.account_sid, 'SmsSid' => 'SM1' }
  end
  let(:status) { { 'MessageSid' => 'SM1', 'MessageStatus' => 'delivered', 'AccountSid' => channel.account_sid, 'From' => channel.phone_number } }

  it 'accepts an inbound message signed with the channel auth token' do
    url = twilio_callback_index_url
    expect do
      post url, params: inbound, headers: { 'X-Twilio-Signature' => tolzar_twilio_signature(channel.auth_token, url, inbound) }
    end.to have_enqueued_job(Webhooks::TwilioEventsJob)
    expect(response).to have_http_status(:no_content)
  end

  it 'refuses an inbound message with no signature or a wrong one (403, nothing enqueued)' do
    url = twilio_callback_index_url
    expect { post url, params: inbound }.not_to have_enqueued_job(Webhooks::TwilioEventsJob)
    expect(response).to have_http_status(:forbidden)

    bad = tolzar_twilio_signature('not-the-token', url, inbound)
    expect { post url, params: inbound, headers: { 'X-Twilio-Signature' => bad } }.not_to have_enqueued_job(Webhooks::TwilioEventsJob)
    expect(response).to have_http_status(:forbidden)

    tampered = tolzar_twilio_signature(channel.auth_token, url, inbound)
    expect do
      post url, params: inbound.merge('Body' => 'spoofed'), headers: { 'X-Twilio-Signature' => tampered }
    end.not_to have_enqueued_job(Webhooks::TwilioEventsJob)
    expect(response).to have_http_status(:forbidden)
  end

  it 'finds the channel by messaging service sid too' do
    mss_channel = create(:channel_twilio_sms)
    params = { 'From' => '+15550001111', 'Body' => 'hi', 'MessagingServiceSid' => mss_channel.messaging_service_sid, 'SmsSid' => 'SM2' }
    post twilio_callback_index_url, params: params
    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts a signature over FRONTEND_URL (Twilio signs the public https URL behind the proxy)' do
    with_modified_env(FRONTEND_URL: 'https://chat.example.com') do
      sig = tolzar_twilio_signature(channel.auth_token, 'https://chat.example.com/twilio/callback', inbound)
      post twilio_callback_index_url, params: inbound, headers: { 'X-Twilio-Signature' => sig }
    end
    expect(response).to have_http_status(:no_content)
  end

  it 'verifies an API-key channel with provider_config webhook_auth_token, and only logs one without it' do
    channel.update!(api_key_sid: "SK#{SecureRandom.hex(16)}")
    post twilio_callback_index_url, params: inbound
    expect(response).to have_http_status(:no_content)

    channel.update!(provider_config: { 'webhook_auth_token' => 'account-auth-token' })
    post twilio_callback_index_url, params: inbound
    expect(response).to have_http_status(:forbidden)
    url = twilio_callback_index_url
    post url, params: inbound, headers: { 'X-Twilio-Signature' => tolzar_twilio_signature('account-auth-token', url, inbound) }
    expect(response).to have_http_status(:no_content)
  end

  it 'keeps a request naming no known channel as before' do
    post twilio_callback_index_url, params: inbound.merge('AccountSid' => 'AC-unknown')
    expect(response).to have_http_status(:no_content)
  end

  it 'verifies delivery status callbacks the same way' do
    url = twilio_delivery_status_index_url
    expect { post url, params: status }.not_to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
    expect(response).to have_http_status(:forbidden)

    expect do
      post url, params: status, headers: { 'X-Twilio-Signature' => tolzar_twilio_signature(channel.auth_token, url, status) }
    end.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
    expect(response).to have_http_status(:no_content)
  end
end

RSpec.describe 'Tolzar M5: SMS (Bandwidth) webhook token', type: :request do
  let(:channel) { create(:channel_sms) }
  let(:events) { [{ type: 'message-received', to: channel.phone_number, message: { id: 'm1', text: 'hi', from: '+15550001111' } }] }

  before { allow(Webhooks::SmsEventsJob).to receive(:perform_later) }

  def deliver(path_suffix = '', headers = {})
    post "/webhooks/sms/#{channel.phone_number.delete('+')}#{path_suffix}", params: events.to_json,
                                                                        headers: { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
  end

  it 'derives a stable per-channel token' do
    expect(channel.webhook_token).to match(/\A\h{64}\z/)
    expect(channel.webhook_token).to eq(Channel::Sms.find(channel.id).webhook_token)
    expect(create(:channel_sms).webhook_token).not_to eq(channel.webhook_token)
    expect(channel.webhook_url).to include("?token=#{channel.webhook_token}")
  end

  it 'accepts the token as the Basic auth password (Bandwidth callbackPassword) or ?token=' do
    deliver('', 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('bandwidth', channel.webhook_token))
    expect(response).to have_http_status(:ok)
    deliver("?token=#{channel.webhook_token}")
    expect(response).to have_http_status(:ok)
    expect(Webhooks::SmsEventsJob).to have_received(:perform_later).twice
  end

  it 'refuses a callback for a known channel with no token or a wrong one' do
    deliver
    expect(response).to have_http_status(:forbidden)
    deliver('?token=wrong')
    expect(response).to have_http_status(:forbidden)
    deliver('', 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('bandwidth', 'wrong'))
    expect(response).to have_http_status(:forbidden)
    expect(Webhooks::SmsEventsJob).not_to have_received(:perform_later)
  end

  it "checks the token of the channel the event is for, not the URL's" do
    other = create(:channel_sms)
    deliver("?token=#{other.webhook_token}")
    expect(response).to have_http_status(:forbidden)
  end
end

RSpec.describe 'Tolzar M5: Telegram webhook secret token', type: :request do
  let(:channel) { create(:channel_telegram) }
  let(:update) { { update_id: 1, message: { text: 'hi' } } }

  before { allow(Webhooks::TelegramEventsJob).to receive(:perform_later) }

  it 'accepts an update carrying the secret token and refuses one without it or with a wrong one' do
    post "/webhooks/telegram/#{channel.bot_token}", params: update, as: :json,
                                                    headers: { 'X-Telegram-Bot-Api-Secret-Token' => channel.webhook_secret_token }
    expect(response).to have_http_status(:success)

    post "/webhooks/telegram/#{channel.bot_token}", params: update, as: :json
    expect(response).to have_http_status(:forbidden)
    post "/webhooks/telegram/#{channel.bot_token}", params: update, as: :json, headers: { 'X-Telegram-Bot-Api-Secret-Token' => 'wrong' }
    expect(response).to have_http_status(:forbidden)
    expect(Webhooks::TelegramEventsJob).to have_received(:perform_later).once
  end

  it 'registers the secret token with setWebhook (allowed characters only)' do
    expect(channel.webhook_secret_token).to match(/\A[A-Za-z0-9_-]{1,256}\z/)
    stub_request(:post, "https://api.telegram.org/bot#{channel.bot_token}/deleteWebhook").to_return(status: 200, body: '{"ok":true}')
    set = stub_request(:post, "https://api.telegram.org/bot#{channel.bot_token}/setWebhook")
          .with(body: hash_including('secret_token' => channel.webhook_secret_token))
          .to_return(status: 200, body: '{"ok":true}')

    Channel::Telegram.find(channel.id).save!
    expect(set).to have_been_requested
  end
end
