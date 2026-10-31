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
