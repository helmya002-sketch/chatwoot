require 'rails_helper'

# Tolzar: the public endpoints Meta calls (Connect Facebook & Instagram). The brain checks the
# signed state and keeps the tokens; these routes only forward.
RSpec.describe 'Tolzar Meta endpoints', type: :request do
  it 'forwards the OAuth callback to the brain and lands on the dashboard' do
    allow(Tolzar::BrainClient).to receive(:post).with('/meta/callback', hash_including(code: 'c', state: '5.n.1.s'))
                                                .and_return({ 'ok' => true, 'account_id' => 5 })
    get '/tolzar/meta/callback', params: { code: 'c', state: '5.n.1.s' }
    expect(response).to redirect_to('/app/accounts/5/dashboard?tolzar_meta=connected')
  end

  it 'reports an error the brain refused' do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'ok' => false, 'error' => 'bad state' })
    get '/tolzar/meta/callback', params: { code: 'c', state: '7.n.1.s' }
    expect(response).to redirect_to('/app/accounts/7/dashboard?tolzar_meta=error')
  end

  it 'answers the data deletion callback with the brain confirmation, or 400' do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'url' => 'https://x/d?code=ab', 'confirmation_code' => 'ab' })
    post '/tolzar/meta/data_deletion', params: { signed_request: 'sig.payload' }
    expect(response.parsed_body).to eq('url' => 'https://x/d?code=ab', 'confirmation_code' => 'ab')

    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'ok' => false })
    post '/tolzar/meta/data_deletion', params: { signed_request: 'bad' }
    expect(response).to have_http_status(:bad_request)
  end
end
