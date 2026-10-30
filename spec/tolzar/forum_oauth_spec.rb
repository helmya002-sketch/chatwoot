require 'rails_helper'

# Tolzar: the app as the community forum's OAuth2 provider (one client, Tolzar users only, no forum registration).
# Red-team suite for the Oracle's guard (30 Oct): every example is an attack or a guard that must hold.
RSpec.describe 'Tolzar forum OAuth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:redirect) { 'https://community.example.test/answer/api/v1/connector/redirect/basic' }
  let(:secret) { 's' * 40 }
  let(:env) do
    { TOLZAR_FORUM_OAUTH_CLIENT_ID: 'forum', TOLZAR_FORUM_OAUTH_CLIENT_SECRET: secret, TOLZAR_FORUM_OAUTH_REDIRECT_URI: redirect }
  end
  let(:code_verifier) { 'v' * 64 }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }
  let(:authorize_params) do
    { response_type: 'code', client_id: 'forum', redirect_uri: redirect, state: 'xyz',
      code_challenge: code_challenge, code_challenge_method: 'S256' }
  end

  around { |example| with_modified_env(env) { example.run } }
  before { Redis::Alfred.delete('tolzar:forum_oauth:token:127.0.0.1') } # the /token limit is per address

  def sign_in_dashboard(as)
    token = as.create_new_auth_token
    cookies['cw_d_session_info'] = { 'access-token' => token['access-token'], 'client' => token['client'], 'uid' => token['uid'] }.to_json
  end

  def approve(extra = {})
    post '/tolzar/oauth/authorize', params: authorize_params.merge(extra)
    Rack::Utils.parse_query(URI(response.location).query)['code'] if response.redirect?
  end

  def exchange(code, extra = {})
    post '/tolzar/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect,
                                          client_id: 'forum', client_secret: secret, code_verifier: code_verifier }.merge(extra)
  end

  describe 'guard 2: exact redirect URI, state passed through' do
    it 'refuses a foreign, prefixed or suffixed redirect without redirecting anywhere' do
      sign_in_dashboard(user)
      ["https://evil.example/cb", "#{redirect}/../evil", "#{redirect}x", redirect.sub('https', 'http')].each do |uri|
        get '/tolzar/oauth/authorize', params: authorize_params.merge(redirect_uri: uri)
        expect(response).to have_http_status(:bad_request)
        expect(response.location).to be_nil
      end
    end

    it 'returns the state unchanged' do
      sign_in_dashboard(user)
      approve
      expect(response.location).to start_with("#{redirect}?").and include('state=xyz')
    end
  end

  describe 'guard 4: an explicit click, never framed, CSRF on the click' do
    it 'shows a consent page on GET (no code issued) that cannot be framed' do
      sign_in_dashboard(user)
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['Content-Security-Policy']).to include("frame-ancestors 'none'")
      expect(response.body).to include('name="code_challenge"')
    end

    it 'accepts the click with the CSRF token from the consent page' do
      sign_in_dashboard(user)
      ActionController::Base.allow_forgery_protection = true
      get '/tolzar/oauth/authorize', params: authorize_params
      token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]
      expect(token).to be_present
      post '/tolzar/oauth/authorize', params: authorize_params.merge(authenticity_token: token)
      expect(response).to have_http_status(:redirect)
      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['Cache-Control']).to include('no-store')
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'refuses the click without the CSRF token (a cross-site auto-submit)' do
      sign_in_dashboard(user)
      ActionController::Base.allow_forgery_protection = true
      post '/tolzar/oauth/authorize', params: authorize_params # the test env renders exceptions (show_exceptions)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.location).to be_nil # no code was issued
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'asks a signed-out visitor to sign in and refuses a user without a workspace' do
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:unauthorized)
      sign_in_dashboard(create(:user))
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'who may sign in' do
    it 'refuses a super admin impersonation session of a customer' do
      token = user.create_token(lifespan: 2.days.to_i, impersonation: true, impersonated_by: 1)
      user.save!
      cookies['cw_d_session_info'] = { 'access-token' => token.token, 'client' => token.client, 'uid' => user.uid }.to_json
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:unauthorized)
    end

    it 'treats a malformed or revoked session cookie as signed out' do
      cookies['cw_d_session_info'] = '[1,2]'
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:unauthorized)
      sign_in_dashboard(user)
      user.update!(tokens: {})
      get '/tolzar/oauth/authorize', params: authorize_params
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['X-Frame-Options']).to eq('DENY')
    end

    it 'refuses the token when the workspace was suspended between the click and the exchange' do
      sign_in_dashboard(user)
      code = approve
      account.update!(status: :suspended)
      exchange(code)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'guard 1: PKCE S256 and a constant-time client secret' do
    it 'accepts the client secret through form-urlencoded Basic auth' do
      sign_in_dashboard(user)
      code = approve
      basic = ActionController::HttpAuthentication::Basic.encode_credentials('forum', CGI.escape(secret))
      post '/tolzar/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect,
                                            code_verifier: code_verifier }, headers: { 'Authorization' => basic }
      expect(response).to have_http_status(:ok)
    end

    it 'refuses an authorize request without S256 PKCE' do
      sign_in_dashboard(user)
      get '/tolzar/oauth/authorize', params: authorize_params.except(:code_challenge, :code_challenge_method)
      expect(response).to have_http_status(:bad_request)
      get '/tolzar/oauth/authorize', params: authorize_params.merge(code_challenge_method: 'plain')
      expect(response).to have_http_status(:bad_request)
    end

    it 'refuses a token request with a wrong verifier or a wrong secret' do
      sign_in_dashboard(user)
      exchange(approve, code_verifier: 'w' * 64)
      expect(response).to have_http_status(:bad_request)
      exchange(approve, client_secret: 'wrong')
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'guard 3: single-use codes, stored hashed' do
    it 'runs code -> token -> userinfo once; the same code a second time is refused' do
      sign_in_dashboard(user)
      code = approve
      expect(Redis::Alfred.get("tolzar:forum_oauth:code:#{code}")).to be_nil # only the hash is a key
      hashed = "tolzar:forum_oauth:code:#{Digest::SHA256.hexdigest(code)}"
      expect(Redis::Alfred.get(hashed)).to be_present
      expect(Redis::Alfred.with { |conn| conn.ttl(hashed) }).to be_between(1, 60)
      exchange(code)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      exchange(code)
      expect(response).to have_http_status(:bad_request)
    end

    it 'refuses a code redeemed with another redirect URI than the one it was issued for' do
      sign_in_dashboard(user)
      exchange(approve, redirect_uri: 'https://evil.example/cb')
      expect(response).to have_http_status(:bad_request)
    end

    it 'refuses an expired code' do
      sign_in_dashboard(user)
      code = approve
      Redis::Alfred.delete("tolzar:forum_oauth:code:#{Digest::SHA256.hexdigest(code)}") # what the 60 s expiry does
      exchange(code)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'guard 5: userinfo returns the minimum' do
    it 'returns id, a non-personal username, display name, locale and email; nothing else' do
      sign_in_dashboard(user)
      exchange(approve)
      get '/tolzar/oauth/userinfo', headers: { 'Authorization' => "Bearer #{response.parsed_body['access_token']}" }
      expect(response.parsed_body.keys).to contain_exactly('id', 'username', 'name', 'locale', 'email')
      expect(response.parsed_body).to include('id' => user.id.to_s, 'email' => user.email)
      expect(response.parsed_body['username']).to match(/\Am\h{12}\z/) # not the sequential id
    end

    it 'refuses a forged, an expired or a newsletter token' do
      get '/tolzar/oauth/userinfo', headers: { 'Authorization' => 'Bearer forged' }
      expect(response).to have_http_status(:unauthorized)
      old = Rails.application.message_verifier(:tolzar_forum_userinfo).generate(user.id, purpose: :tolzar_forum_userinfo,
                                                                                         expires_in: 10.minutes)
      travel 11.minutes do
        get '/tolzar/oauth/userinfo', headers: { 'Authorization' => "Bearer #{old}" }
        expect(response).to have_http_status(:unauthorized)
      end
      other = Rails.application.message_verifier(:tolzar_newsletter_unsubscribe).generate(user.id, purpose: :tolzar_newsletter_unsubscribe)
      get '/tolzar/oauth/userinfo', headers: { 'Authorization' => "Bearer #{other}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'guard 6: rate limit on /token' do
    it 'answers 429 after 60 token requests a minute from one address' do
      60.times { exchange('nope') }
      expect(response).to have_http_status(:bad_request)
      exchange('nope')
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
