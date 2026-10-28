require 'rails_helper'

# Tolzar: the public endpoints Meta calls (Connect Facebook & Instagram). The brain checks the
# signed state and keeps the tokens; these routes only forward.
#
# End-to-end-ish (N1): Tolzar::BrainClient is NOT stubbed, only the HTTP layer (WebMock), so the
# exact request the fork sends is pinned: the public callback has no session, so it signs account
# 0 (H1) and sends no X-Tolzar-Actor; the brain proves the workspace from the state, and that this
# browser started the link from sha256 of the tolzar_meta_bind cookie (login-CSRF binding).
RSpec.describe 'Tolzar Meta endpoints', type: :request do
  let(:secret) { 'tolzar-test-secret-0123456789abcdef' }
  let(:brain) { 'http://tolzar-brain:8080' }

  around { |example| with_modified_env(TOLZAR_BRAIN_SECRET: secret, TOLZAR_BRAIN_URL: brain) { example.run } }

  let(:bind) { 'browser-bind-value' }
  let(:bind_hash) { Digest::SHA256.hexdigest(bind) }
  let(:with_cookie) { { 'Cookie' => "tolzar_meta_bind=#{bind}" } }

  before { https! }   # the bind cookie is Secure: Rails writes it only on an https request

  def expected_sig(account_id, ts, method, path, body)
    OpenSSL::HMAC.hexdigest('SHA256', secret,
                            "v2\n#{account_id}\n#{ts}\n#{method}\n#{path}\n#{Digest::SHA256.hexdigest(body.to_s)}")
  end

  def set_cookies
    Array(response.headers['Set-Cookie']).join("\n").split("\n").grep(/\Atolzar_meta_bind=/)
  end

  def stub_callback(response)
    seen = {}
    stub = stub_request(:post, "#{brain}/meta/callback").with do |req|
      seen[:headers] = req.headers
      seen[:raw] = req.body
      seen[:body] = JSON.parse(req.body)
      true
    end.to_return(body: response.to_json, headers: { 'Content-Type' => 'application/json' })
    [stub, seen]
  end

  describe 'POST connect_url (where the link is bound to the workspace and the user)' do
    let(:account) { create(:account) }
    let!(:owner) { create(:user, account: account, role: :administrator) }

    it 'signs the URL account, names the signed-in user and binds the link to this browser' do
      seen = {}
      stub = stub_request(:post, "#{brain}/meta/connect_url").with do |req|
        seen[:headers] = req.headers
        seen[:raw] = req.body
        seen[:body] = JSON.parse(req.body)
        true
      end.to_return(body: { ok: true, url: 'https://www.facebook.com/v21.0/dialog/oauth?state=x' }.to_json)
      post "/api/v1/accounts/#{account.id}/tolzar/meta/connect_url", headers: owner.create_new_auth_token, as: :json

      expect(stub).to have_been_requested.once
      expect(response.parsed_body['url']).to start_with('https://www.facebook.com/')
      headers = seen[:headers]
      expect(headers['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(headers['X-Tolzar-Body-Sha256']).to eq(Digest::SHA256.hexdigest(seen[:raw]))
      expect(headers['X-Tolzar-Sig']).to eq(expected_sig(account.id, headers['X-Tolzar-Ts'], 'POST', '/meta/connect_url', seen[:raw]))
      expect(headers['X-Tolzar-Actor']).to eq("#{owner.id}:#{owner.email}")

      # the cookie: random 32 bytes, HttpOnly, Secure, SameSite=Lax, scoped to the callback, 15 min
      cookie = set_cookies.first
      expect(cookie).to be_present
      value = cookie[/\Atolzar_meta_bind=([^;]+)/, 1]
      expect(Base64.urlsafe_decode64(value).bytesize).to eq(32)
      attrs = cookie.downcase.split(/;\s*/)
      expect(attrs).to include('httponly', 'secure', 'samesite=lax', 'path=/tolzar/meta', 'max-age=900')
      # the brain gets only its sha256
      expect(seen[:body]).to eq('account_id' => account.id, 'bind_hash' => Digest::SHA256.hexdigest(value))
      expect(seen[:raw]).not_to include(value)
    end

    it 'sets a fresh value on every start' do
      stub_request(:post, "#{brain}/meta/connect_url").to_return(body: { ok: true, url: 'https://www.facebook.com/x' }.to_json)
      post "/api/v1/accounts/#{account.id}/tolzar/meta/connect_url", headers: owner.create_new_auth_token, as: :json
      first = set_cookies.first
      post "/api/v1/accounts/#{account.id}/tolzar/meta/connect_url", headers: owner.create_new_auth_token, as: :json
      expect(set_cookies.first).to be_present
      expect(set_cookies.first[/=([^;]+)/, 1]).not_to eq(first[/=([^;]+)/, 1])
    end
  end

  describe 'GET /tolzar/meta/callback' do
    it 'sends the exact signed request and lands on the account the brain verified' do
      # The state string starts with "5": the redirect must follow the brain's answer (9), never the state.
      stub, seen = stub_callback({ ok: true, account_id: 9 })
      get '/tolzar/meta/callback', params: { code: 'c0de', state: '5.payload.sig' }, headers: with_cookie

      expect(stub).to have_been_requested.once
      headers = seen[:headers]
      expect(seen[:body]).to eq('code' => 'c0de', 'state' => '5.payload.sig', 'bind_hash' => bind_hash)
      expect(seen[:raw]).not_to include(bind)
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['X-Tolzar-Brain-Secret']).to eq(secret)
      expect(headers['X-Tolzar-Account']).to eq('0')
      expect(headers['X-Tolzar-Ts'].to_i).to be_within(60).of(Time.now.to_i)
      expect(headers['X-Tolzar-Body-Sha256']).to eq(Digest::SHA256.hexdigest(seen[:raw]))
      expect(headers['X-Tolzar-Sig']).to eq(expected_sig(0, headers['X-Tolzar-Ts'], 'POST', '/meta/callback', seen[:raw]))
      expect(headers.keys.map(&:downcase)).not_to include('x-tolzar-actor')
      expect(response).to redirect_to('/app/accounts/9/dashboard?tolzar_meta=connected')
      # the bind cookie is cleared (one connect per cookie)
      cleared = set_cookies.first.to_s.downcase
      expect(cleared).to start_with('tolzar_meta_bind=')
      expect(cleared).to include('path=/tolzar/meta')
      expect(cleared).to match(/max-age=0|expires=thu, 01 jan 1970/)
    end

    it 'refuses without the bind cookie: neutral error page, the brain is never asked' do
      stub = stub_request(:post, "#{brain}/meta/callback")
      get '/tolzar/meta/callback', params: { code: 'c0de', state: '5.payload.sig' }
      expect(stub).not_to have_been_requested
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'lands on the error page when the brain refuses this browser (cookie of another start)' do
      _stub, seen = stub_callback({ ok: false, error: 'this connect link was not started in this browser; start again' })
      get '/tolzar/meta/callback', params: { code: 'c', state: '1.p.s' }, headers: { 'Cookie' => 'tolzar_meta_bind=other' }
      expect(seen[:body]['bind_hash']).to eq(Digest::SHA256.hexdigest('other'))
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'forwards a Meta error (user cancelled) and lands on the neutral error page' do
      _stub, seen = stub_callback({ ok: false, error: 'Permissions error' })
      get '/tolzar/meta/callback', params: { error: 'access_denied', error_description: 'Permissions error', state: '7.p.s' },
                                   headers: with_cookie

      expect(seen[:body]).to eq('code' => '', 'state' => '7.p.s', 'bind_hash' => bind_hash, 'error' => 'access_denied',
                                'error_description' => 'Permissions error')
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'never guesses an account when the brain refuses the state, even if it names one' do
      stub_callback({ ok: false, error: 'this connect link was already used', account_id: 3 })
      get '/tolzar/meta/callback', params: { code: 'c', state: '1.p.s' }, headers: with_cookie
      expect(response).to redirect_to('/tolzar/meta/error')
    end

    it 'lands on the neutral error page when the brain is unreachable' do
      stub_request(:post, "#{brain}/meta/callback").to_raise(Errno::ECONNREFUSED)
      get '/tolzar/meta/callback', params: { code: 'c', state: '1.p.s' }, headers: with_cookie
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
    raw = nil
    stub_request(:post, "#{brain}/meta/data_deletion").with { |req| (raw = req.body) && (seen = req.headers) }
                                                      .to_return(body: { url: 'https://x/d?code=ab', confirmation_code: 'ab' }.to_json)
    post '/tolzar/meta/data_deletion', params: { signed_request: 'sig.payload' }
    expect(response.parsed_body).to eq('url' => 'https://x/d?code=ab', 'confirmation_code' => 'ab')
    expect(seen['X-Tolzar-Account']).to eq('0')
    expect(seen['X-Tolzar-Sig']).to eq(expected_sig(0, seen['X-Tolzar-Ts'], 'POST', '/meta/data_deletion', raw))

    stub_request(:post, "#{brain}/meta/data_deletion").to_return(status: 400, body: { detail: 'bad signed_request' }.to_json)
    post '/tolzar/meta/data_deletion', params: { signed_request: 'bad' }
    expect(response).to have_http_status(:bad_request)
  end
end
