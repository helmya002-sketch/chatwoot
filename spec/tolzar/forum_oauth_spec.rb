require 'rails_helper'

# Tolzar: the app as the community forum's OAuth2 provider (one client, Tolzar users only, no forum registration).
RSpec.describe 'Tolzar forum OAuth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:redirect) { 'https://community.example.test/answer/api/v1/connector/redirect/basic' }
  let(:env) do
    { TOLZAR_FORUM_OAUTH_CLIENT_ID: 'forum', TOLZAR_FORUM_OAUTH_CLIENT_SECRET: 's' * 40,
      TOLZAR_FORUM_OAUTH_REDIRECT_URI: redirect }
  end
  let(:authorize_params) { { response_type: 'code', client_id: 'forum', redirect_uri: redirect, state: 'xyz' } }

  around { |example| with_modified_env(env) { example.run } }

  def sign_in_dashboard(as)
    token = as.create_new_auth_token
    cookies['cw_d_session_info'] = { 'access-token' => token['access-token'], 'client' => token['client'], 'uid' => token['uid'] }.to_json
  end

  def code_from(location)
    Rack::Utils.parse_query(URI(location).query)['code']
  end

  it 'refuses a wrong client or redirect without redirecting anywhere' do
    get '/tolzar/oauth/authorize', params: authorize_params.merge(redirect_uri: 'https://evil.example/cb')
    expect(response).to have_http_status(:bad_request)
    get '/tolzar/oauth/authorize', params: authorize_params.merge(client_id: 'other')
    expect(response).to have_http_status(:bad_request)
  end

  it 'asks a signed-out visitor to sign in to Tolzar, and refuses a user without a workspace' do
    get '/tolzar/oauth/authorize', params: authorize_params
    expect(response).to have_http_status(:unauthorized)

    sign_in_dashboard(create(:user))
    get '/tolzar/oauth/authorize', params: authorize_params
    expect(response).to have_http_status(:forbidden)
  end

  it 'runs the code flow once: code -> token -> userinfo; the code is single-use' do
    sign_in_dashboard(user)
    get '/tolzar/oauth/authorize', params: authorize_params
    expect(response).to have_http_status(:redirect)
    expect(response.location).to start_with(redirect).and include('state=xyz')
    code = code_from(response.location)

    post '/tolzar/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect,
                                          client_id: 'forum', client_secret: 's' * 40 }
    expect(response).to have_http_status(:ok)
    access = response.parsed_body['access_token']

    get '/tolzar/oauth/userinfo', headers: { 'Authorization' => "Bearer #{access}" }
    expect(response.parsed_body).to include('id' => user.id.to_s, 'email' => user.email, 'username' => "u#{user.id}")

    post '/tolzar/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect,
                                          client_id: 'forum', client_secret: 's' * 40 }
    expect(response).to have_http_status(:bad_request)
  end

  it 'refuses a wrong client secret, a forged bearer and an expired token' do
    sign_in_dashboard(user)
    get '/tolzar/oauth/authorize', params: authorize_params
    code = code_from(response.location)
    post '/tolzar/oauth/token', params: { grant_type: 'authorization_code', code: code, redirect_uri: redirect,
                                          client_id: 'forum', client_secret: 'wrong' }
    expect(response).to have_http_status(:unauthorized)

    get '/tolzar/oauth/userinfo', headers: { 'Authorization' => 'Bearer forged' }
    expect(response).to have_http_status(:unauthorized)

    old = Rails.application.message_verifier(:tolzar_forum_userinfo).generate(user.id, purpose: :tolzar_forum_userinfo, expires_in: 10.minutes)
    travel 11.minutes do
      get '/tolzar/oauth/userinfo', headers: { 'Authorization' => "Bearer #{old}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
