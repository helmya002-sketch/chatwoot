require 'rails_helper'

# Booking-system events into Tolzar: signed (timestamp + HMAC), within 5 minutes, each once; the contact moves to
# the won / lost stage (forward only) and the conversation gets an activity line; nothing is sent.
RSpec.describe 'Tolzar booking hooks', type: :request do
  let(:account) { create(:account) }
  let(:connector) do
    Tolzar::BookingConnector.create!(account: account, adapter: 'dwt', base_url: 'https://b.example.com/api.php', token: 'dwtbk_x')
  end
  let(:contact) { create(:contact, account: account, custom_attributes: { 'lifecycle_stage' => 'Offer Sent Follow up' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  around { |example| with_modified_env(TOLZAR_BOOKING_CONNECTOR: account.id.to_s) { example.run } }

  def deliver(payload, ts: Time.current.to_i, secret: Tolzar::BookingHook.secret(connector))
    body = payload.to_json
    sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")}"
    headers = { 'Content-Type' => 'application/json', 'X-Tolzar-Timestamp' => ts.to_s, 'X-Tolzar-Signature' => sig }
    post "/tolzar/booking_hooks/#{connector.id}", params: body, headers: headers
  end

  let(:confirmed) do
    { id: "evt-#{SecureRandom.hex(6)}", event: 'booking.confirmed', voucher_no: 'DWT-26-0002', tolzar_contact_id: contact.id.to_s,
      tolzar_conversation_id: conversation.display_id.to_s, balance: '50', currency: 'EUR' }
  end

  it 'moves the contact to the won stage, notes it in the conversation, and takes each event once' do
    deliver(confirmed)
    expect(response.parsed_body['result']).to eq('done')
    expect(contact.reload.custom_attributes).to include('lifecycle_stage' => 'Customer Won', 'booking_ref' => 'DWT-26-0002')
    note = conversation.messages.activity.last
    expect(note.content).to eq('Booking system: DWT-26-0002 confirmed (balance EUR 50)')
    expect { deliver(confirmed) }.not_to change(Message, :count)
    expect(response.parsed_body['result']).to eq('duplicate')
  end

  it 'never moves a won contact back by a later cancellation event of another booking' do
    contact.update!(custom_attributes: { 'lifecycle_stage' => 'Customer Won' })
    deliver(confirmed.merge(id: "evt-2-#{SecureRandom.hex(6)}", event: 'booking.cancelled'))
    expect(contact.reload.custom_attributes['lifecycle_stage']).to eq('Customer Won')
  end

  it 'refuses a bad signature, a stale timestamp and an unknown event; 404 when switched off' do
    deliver(confirmed, secret: 'wrong')
    expect(response).to have_http_status(:unauthorized)
    deliver(confirmed, ts: 10.minutes.ago.to_i)
    expect(response).to have_http_status(:unauthorized)
    deliver(confirmed.merge(id: "evt-3-#{SecureRandom.hex(6)}", event: 'booking.deleted'))
    expect(response).to have_http_status(:unprocessable_entity)
    with_modified_env(TOLZAR_BOOKING_CONNECTOR: '') do
      deliver(confirmed.merge(id: "evt-4-#{SecureRandom.hex(6)}"))
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'shows the webhook URL and secret to the owner only' do
    owner = create(:user, account: account, role: :administrator)
    agent = create(:user, account: account, role: :agent)
    connector
    get "/api/v1/accounts/#{account.id}/tolzar/booking_connector", headers: agent.create_new_auth_token
    expect(response.parsed_body['webhook']).to be_nil
    get "/api/v1/accounts/#{account.id}/tolzar/booking_connector", headers: owner.create_new_auth_token
    expect(response.parsed_body['webhook']).to include('secret' => Tolzar::BookingHook.secret(connector))
    expect(response.parsed_body.dig('webhook', 'url')).to end_with("/tolzar/booking_hooks/#{connector.id}")
  end
end
