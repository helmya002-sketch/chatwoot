require 'rails_helper'

RSpec.describe 'Tolzar::Mirror::Respondio', type: :request do
  let(:key) { 'test-signing-key-aquarius' }
  let(:body) do
    { event_type: 'message.received', event_id: 'evt-1',
      contact: { id: 7 }, message: { messageId: 99 } }.to_json
  end
  let(:sig) { Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', key, body)) }
  let(:json_headers) { { 'X-Webhook-Signature' => sig, 'CONTENT_TYPE' => 'application/json' } }

  before { ENV['TOLZAR_MIRROR_KEYS_AQUARIUS'] = key }
  after  { ENV.delete('TOLZAR_MIRROR_KEYS_AQUARIUS') }

  it 'stores a signed event and returns 200' do
    expect do
      post '/tolzar/mirror/respondio/aquarius', params: body, headers: json_headers
    end.to change(Tolzar::MirrorEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    ev = Tolzar::MirrorEvent.last
    expect(ev.tenant).to eq('aquarius')
    expect(ev.event_type).to eq('message.received')
    expect(ev.rio_contact_id).to eq(7)
    expect(ev.rio_message_id).to eq(99)
  end

  it 'rejects a bad signature and stores nothing' do
    post '/tolzar/mirror/respondio/aquarius', params: body,
         headers: { 'X-Webhook-Signature' => 'wrong', 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
    expect(Tolzar::MirrorEvent.count).to eq(0)
  end

  it '404s an unknown tenant' do
    post '/tolzar/mirror/respondio/nope', params: body, headers: json_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'is idempotent on event_id (duplicate delivery)' do
    2.times { post '/tolzar/mirror/respondio/aquarius', params: body, headers: json_headers }
    expect(Tolzar::MirrorEvent.where(event_id: 'evt-1').count).to eq(1)
  end
end
