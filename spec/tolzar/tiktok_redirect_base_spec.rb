require 'rails_helper'

# TikTok (owner's choice, 31 Oct): TikTok users see Tolzar's domain. The OAuth redirect and the webhook use
# TIKTOK_REDIRECT_BASE (app.tolzar.com) while the dashboard and its sign-in stay on FRONTEND_URL.
RSpec.describe 'Tolzar TikTok redirect base' do
  let(:env) { { FRONTEND_URL: 'https://chat.example.com', TIKTOK_REDIRECT_BASE: 'https://app.tolzar.com/' } }

  it 'builds the OAuth redirect and the webhook URL on TIKTOK_REDIRECT_BASE' do
    with_modified_env(env) do
      expect(Tiktok::AuthClient.send(:redirect_uri)).to eq('https://app.tolzar.com/tiktok/callback')
      expect(Tiktok::AuthClient.send(:webhook_url)).to eq('https://app.tolzar.com/webhooks/tiktok')
    end
  end

  it 'falls back to FRONTEND_URL when TIKTOK_REDIRECT_BASE is unset' do
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TIKTOK_REDIRECT_BASE: nil) do
      expect(Tiktok::AuthClient.send(:redirect_uri)).to eq('https://chat.example.com/tiktok/callback')
    end
  end

  it 'sends the user back to the dashboard host after the callback' do
    with_modified_env(env) do
      expect(Tolzar::PublicUrls.dashboard_url_options).to eq(host: 'chat.example.com', protocol: 'https')
    end
    with_modified_env(FRONTEND_URL: 'http://localhost:3000') do
      expect(Tolzar::PublicUrls.dashboard_url_options).to eq(host: 'localhost', protocol: 'http', port: 3000)
    end
  end
end

# The callback itself (c19 gate: a private url_options made every redirect a 500). Without TIKTOK_REDIRECT_BASE the
# redirect stays on the request's host, as upstream; with it, it goes to the dashboard (FRONTEND_URL).
RSpec.describe 'Tolzar TikTok callback redirect host', type: :request do
  let(:account) { create(:account) }
  let(:state) { JWT.encode({ sub: account.id, iat: Time.current.to_i }, 'tiktok-app-secret', 'HS256') }

  def deny
    get '/tiktok/callback', params: { error: 'access_denied', error_description: 'User cancelled', error_code: '400', state: state }
  end

  before do
    InstallationConfig.where(name: %w[TIKTOK_APP_ID TIKTOK_APP_SECRET]).delete_all
    GlobalConfig.clear_cache
  end

  it 'redirects on the request host when TIKTOK_REDIRECT_BASE and FRONTEND_URL are unset' do
    with_modified_env(TIKTOK_APP_ID: 'id', TIKTOK_APP_SECRET: 'tiktok-app-secret', TIKTOK_REDIRECT_BASE: nil, FRONTEND_URL: nil) do
      deny
    end
    expect(response).to have_http_status(:redirect)
    expect(URI.parse(response.location).host).to eq('www.example.com')
  end

  it 'redirects to the dashboard host when the callback came in on TIKTOK_REDIRECT_BASE' do
    with_modified_env(TIKTOK_APP_ID: 'id', TIKTOK_APP_SECRET: 'tiktok-app-secret',
                      TIKTOK_REDIRECT_BASE: 'https://app.tolzar.com', FRONTEND_URL: 'https://chat.example.com') do
      deny
    end
    expect(response).to have_http_status(:redirect)
    expect(URI.parse(response.location).host).to eq('chat.example.com')
  end
end

RSpec.describe 'Tolzar Meta webhook base' do
  it 'keeps the registered Meta webhook host when FRONTEND_URL moves' do
    app = Tolzar::MetaApp.new(webhook_token: 'tok')
    with_modified_env(FRONTEND_URL: 'https://app.tolzar.com', TOLZAR_META_WEBHOOK_BASE: 'https://chat.example.com') do
      expect(app.webhook_url).to eq('https://chat.example.com/tolzar/meta/hook/tok')
    end
    with_modified_env(FRONTEND_URL: 'https://app.tolzar.com', TOLZAR_META_WEBHOOK_BASE: nil) do
      expect(app.webhook_url).to eq('https://app.tolzar.com/tolzar/meta/hook/tok')
    end
  end
end
