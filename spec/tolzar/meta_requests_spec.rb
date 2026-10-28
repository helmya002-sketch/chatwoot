require 'rails_helper'

# Tolzar: the public endpoints Meta calls (Connect Facebook & Instagram). The brain checks the
# signed state and keeps the tokens; these routes only forward.
#
# End-to-end-ish (N1): Tolzar::BrainClient is NOT stubbed, only the HTTP layer (WebMock), so the
# exact request the fork sends is pinned: the public callback has no session, so it signs account
# 0 (H1) and sends no X-Tolzar-Actor; the brain proves everything from the state alone.
RSpec.describe 'Tolzar Meta endpoints', type: :request do
  let(:secret) { 'tolzar-test-secret-0123456789abcdef' }
  let(:brain) { 'http://tolzar-brain:8080' }

  around { |example| with_modified_env(TOLZAR_BRAIN_SECRET: secret, TOLZAR_BRAIN_URL: brain) { example.run } }

  def expected_sig(account_id, ts, method, path)
    OpenSSL::HMAC.hexdigest('SHA256', secret, "v1\n#{account_id}\n#{ts}\n#{method}\n#{path}")
  end

  def stub_callback(response)
    seen = {}
    stub = stub_request(:post, "#{brain}/meta/callback").with do |req|
      seen[:headers] = req.headers
      seen[:body] = JSON.parse(req.body)
      true
    end.to_return(body: response.to_json, headers: { 'Content-Type' => 'application/json' })
    [stub, seen]
  end

  describe 'POST connect_url (where the link is bound to the workspace and the user)' do
    let(:account) { create(:account) }
    let!(:owner) { create(:user, account: account, role: :administrator) }

    it 'signs the URL account and names the signed-in user to the brain' do
      seen = {}
      stub = stub_request(:post, "#{brain}/meta/connect_url").with do |req|
        seen[:headers] = req.headers
        seen[:body] = JSON.parse(req.body)
        true
      end.to_return(body: { ok: true, url: 'https://www.facebook.com/v21.0/dialog/oauth?state=x' }.to_json)
      post "/api/v1/accounts/#{account.id}/tolzar/meta/connect_url", headers: owner.create_new_auth_token, as: :json

      expect(stub).to have_been_requested.once
      expect(response.parsed_body['url']).to start_with('https://www.facebook.com/')
      headers = seen[:headers]
      expect(headers['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(headers['X-Tolzar-Sig']).to eq(expected_sig(account.id, headers['X-Tolzar-Ts'], 'POST', '/meta/connect_url'))
      expect(headers['X-Tolzar-Actor']).to eq("#{owner.id}:#{owner.email}")
      expect(seen[:body]).to eq('account_id' => account.id)
    end
  end

  describe 'GET /tolzar/meta/callback' do
    it 'sends the exact signed request and lands on the account the brain verified' do
      # The state string starts with "5": the redirect must follow the brain's answer (9), never the state.
      stub, seen = stub_callback({ ok: true, account_id: 9 })
      get '/tolzar/meta/callback', params: { code: 'c0de', state: '5.payload.sig' }

      expect(stub).to have_been_requested.once
      headers = seen[:headers]
      expect(seen[:body]).to eq('code' => 'c0de', 'state' => '5.payload.sig')
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['X-Tolzar-Brain-Secret']).to eq(secret)
      expect(headers['X-Tolzar-Account']).to eq('0')
      expect(headers['X-Tolzar-Ts'].to_i).to be_within(60).of(Time.now.to_i)
      expect(headers['X-Tolzar-Sig']).to eq(expected_sig(0, headers['X-Tolzar-Ts'], 'POST', '/meta/callback'))
      expect(headers.keys.map(&:downcase)).not_to include('x-tolzar-actor')
      expect(response).to redirect_to('/app/accounts/9/dashboard?tolzar_meta=connected')
    end

    it 'forwards a Meta error (user cancelled) and lands on the neutral error page' do
      _stub, seen = stub_callback({ ok: false, error: 'Permissions error' })
      get '/tolzar/meta/callback', params: { error: 'access_denied', error_description: 'Permissions error', state: '7.p.s' }

      expect(seen[:body]).to eq('code' => '', 'state' => '7.p.s', 'error' => 'access_denied',
                                'error_description' => 'Permissions error')
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'never guesses an account when the brain refuses the state, even if it names one' do
      stub_callback({ ok: false, error: 'this connect link was already used', account_id: 3 })
      get '/tolzar/meta/callback', params: { code: 'c', state: '1.p.s' }
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'lands on the neutral error page when the brain is unreachable' do
      stub_request(:post, "#{brain}/meta/callback").to_raise(Errno::ECONNREFUSED)
      get '/tolzar/meta/callback', params: { code: 'c', state: '1.p.s' }
      expect(response).to redirect_to('/tolzar/meta/error')
    end
  end

  it 'shows a neutral error page that names no workspace' do
    get '/tolzar/meta/error'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('not connected')
  end

  it 'answers the data deletion callback with the brain confirmation, or 400' do
    seen = nil
    stub_request(:post, "#{brain}/meta/data_deletion").with { |req| seen = req.headers }
                                                      .to_return(body: { url: 'https://x/d?code=ab', confirmation_code: 'ab' }.to_json)
    post '/tolzar/meta/data_deletion', params: { signed_request: 'sig.payload' }
    expect(response.parsed_body).to eq('url' => 'https://x/d?code=ab', 'confirmation_code' => 'ab')
    expect(seen['X-Tolzar-Account']).to eq('0')
    expect(seen['X-Tolzar-Sig']).to eq(expected_sig(0, seen['X-Tolzar-Ts'], 'POST', '/meta/data_deletion'))

    stub_request(:post, "#{brain}/meta/data_deletion").to_return(status: 400, body: { detail: 'bad signed_request' }.to_json)
    post '/tolzar/meta/data_deletion', params: { signed_request: 'bad' }
    expect(response).to have_http_status(:bad_request)
  end
end
