require 'rails_helper'

RSpec.describe 'Tolzar::Mirror::Status', type: :request do
  let(:key) { 'test-signing-key-aquarius' }

  before { ENV['TOLZAR_MIRROR_KEYS_AQUARIUS'] = key }
  after  { ENV.delete('TOLZAR_MIRROR_KEYS_AQUARIUS') }

  it 'requires the shared key' do
    get '/tolzar/mirror/status/aquarius'
    expect(response).to have_http_status(:unauthorized)
    get '/tolzar/mirror/status/aquarius', headers: { 'X-Tolzar-Mirror-Key' => 'wrong' }
    expect(response).to have_http_status(:unauthorized)
  end

  it '404s an unknown tenant even with a key' do
    get '/tolzar/mirror/status/nope', headers: { 'X-Tolzar-Mirror-Key' => key }
    expect(response).to have_http_status(:not_found)
  end

  it 'returns per-tenant counts for a valid key' do
    Tolzar::MirrorEvent.create!(tenant: 'aquarius', event_id: 's-1', event_type: 'message.received',
                                payload: {}, received_at: Time.current)
    Tolzar::MirrorEvent.create!(tenant: 'aquarius', event_id: 's-2', event_type: 'conversation.closed',
                                payload: {}, received_at: Time.current, processed_at: Time.current)
    get '/tolzar/mirror/status/aquarius', headers: { 'X-Tolzar-Mirror-Key' => key }
    expect(response).to have_http_status(:ok)
    j = JSON.parse(response.body)
    expect(j['total']).to eq(2)
    expect(j['pending']).to eq(1)
    expect(j['processed']).to eq(1)
    expect(j['recent'].map { |r| r['event_id'] }).to contain_exactly('s-1', 's-2')
    expect(j['recent'].first).not_to have_key('payload')
  end
end
