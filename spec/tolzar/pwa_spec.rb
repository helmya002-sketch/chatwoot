require 'rails_helper'

# Tolzar installable app (round 4, c63): Safari's Add to Home Screen gives a full-screen Tolzar with our icon and a
# splash; the service worker never caches data; the web-push keys are stored as a secret.
RSpec.describe 'Tolzar installable app', type: :request do
  it 'serves the iPhone install tags, the icon and a splash for every listed screen' do
    InstallationConfig.find_or_initialize_by(name: 'DISPLAY_MANIFEST').update!(value: true)
    GlobalConfig.clear_cache
    get '/app/login'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="apple-mobile-web-app-capable" content="yes"', 'apple-mobile-web-app-title" content="Tolzar"',
                                      'viewport-fit=cover', 'href="/apple-icon-180x180.png"', 'rel="manifest"')
    splashes = response.body.scan(%r{href="/tz/splash/(splash-\d+x\d+\.png)"}).flatten
    expect(splashes.size).to be >= 10
    splashes.each { |file| expect(Rails.public_path.join('tz/splash', file)).to exist }
  end

  it 'has a manifest that installs as Tolzar, full screen, with a maskable icon' do
    manifest = JSON.parse(Rails.public_path.join('manifest.json').read)
    expect(manifest).to include('name' => 'Tolzar', 'display' => 'standalone', 'start_url' => '/app/')
    expect(manifest['icons'].pluck('purpose')).to include('maskable')
    manifest['icons'].each { |icon| expect(Rails.public_path.join(icon['src'].delete_prefix('/'))).to exist }
  end

  it 'never caches data in the service worker, and has a script-free offline page' do
    sw = Rails.public_path.join('sw.js').read
    expect(sw).to include("request.mode === 'navigate'", 'tz-clear-caches')
    expect(sw).not_to match(%r{CACHEABLE = .*/api}) # only build files and icons are cacheable
    offline = Rails.public_path.join('offline.html').read
    expect(offline).not_to include('<script', 'onclick')
  end

  it 'turns the phone layouts on only for TOLZAR_PWA_ACCOUNTS workspaces (c65)' do
    account = create(:account)
    admin = create(:user, account: account, role: :administrator)
    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['tolzar_pwa']).to be(false)
    with_modified_env(TOLZAR_PWA_ACCOUNTS: account.id.to_s) do
      get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token
      expect(response.parsed_body['tolzar_pwa']).to be(true)
    end
  end

  it 'stores the web-push (VAPID) keys as a secret' do
    expect(Tolzar::EncryptedInstallationConfig.secret_name?('VAPID_KEYS')).to be(true)
    expect(Tolzar::EncryptedInstallationConfig.secret_name?('VAPID_KEYS_ENABLED')).to be(false)
  end
end
