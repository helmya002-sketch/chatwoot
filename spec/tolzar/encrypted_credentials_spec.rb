require 'rails_helper'

# Tolzar W9 (Oracle 31 Oct): every channel / integration credential is encrypted at rest and still readable.
# Needs the ACTIVE_RECORD_ENCRYPTION_* keys at boot. The gate runs this file a second time with the public
# test keys of .github/workflows/run_mfa_spec.yml; without keys every example is skipped.
RSpec.describe 'Tolzar encrypted credentials' do
  before { skip 'ACTIVE_RECORD_ENCRYPTION_* keys are not set' unless Chatwoot.encryption_configured? }

  let(:account) { create(:account) }

  def raw(record, column)
    record.class.connection.select_value(
      record.class.unscoped.where(id: record.id).select(column).to_sql
    )
  end

  def json(record, column)
    value = raw(record, column)
    value.is_a?(String) ? JSON.parse(value) : value
  end

  describe 'WhatsApp Cloud: the access token and PIN leave provider_config' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false)
    end

    it 'stores api_key / verification_pin / webhook_verify_token encrypted and reads them back unchanged' do
      channel.provider_config['verification_pin'] = 123_456
      channel.save!

      stored = json(channel, :provider_config)
      expect(stored.keys).not_to include('api_key', 'verification_pin', 'webhook_verify_token')
      expect(stored['phone_number_id']).to eq('123456789') # lookups still query the JSON
      expect(ActiveRecord::Encryption.encryptor.encrypted?(raw(channel, :tolzar_secrets))).to be(true)

      reloaded = Channel::Whatsapp.find(channel.id)
      expect(reloaded.provider_config['api_key']).to eq('test_key')
      expect(reloaded.provider_config['verification_pin']).to eq(123_456)
      expect(reloaded.provider_config['webhook_verify_token']).to be_present
      expect(reloaded.changed?).to be(false)
      expect(Channel::Whatsapp.where("provider_config->>'phone_number_id' = ?", '123456789')).to include(reloaded)
    end

    it 'keeps a value set in memory and drops a key removed from the hash' do
      reloaded = Channel::Whatsapp.find(channel.id)
      reloaded.provider_config = reloaded.provider_config.merge('api_key' => 'rotated').except('verification_pin')
      reloaded.save!
      again = Channel::Whatsapp.find(channel.id)
      expect(again.provider_config['api_key']).to eq('rotated')
      expect(again.provider_config).not_to have_key('verification_pin')
    end

    it 'still reads a row written before the move, and the task moves it' do
      channel.class.where(id: channel.id).update_all(tolzar_secrets: nil, # rubocop:disable Rails/SkipsModelValidations
                                                     provider_config: channel.provider_config.merge('api_key' => 'legacy'))
      legacy = Channel::Whatsapp.find(channel.id)
      expect(legacy.provider_config['api_key']).to eq('legacy')
      expect(legacy.tolzar_json_secrets_pending?).to be(true)

      Tolzar::CredentialsTask.encrypt!
      moved = Channel::Whatsapp.find(channel.id)
      expect(moved.tolzar_json_secrets_pending?).to be(false)
      expect(moved.provider_config['api_key']).to eq('legacy')
    end
  end

  it 'encrypts the e-mail OAuth tokens and a LeadSquared hook\'s keys the same way' do
    email = create(:channel_email, account: account, provider_config: { 'access_token' => 'oauth-a', 'refresh_token' => 'oauth-r' })
    expect(json(email, :provider_config).keys).not_to include('access_token', 'refresh_token')
    expect(Channel::Email.find(email.id).provider_config['refresh_token']).to eq('oauth-r')

    settings = { 'access_key' => 'ak', 'secret_key' => 'sk', 'endpoint_url' => 'https://x.test' }
    hook = Integrations::Hook.new(account: account, app_id: 'leadsquared', hook_type: 'account', settings: settings)
    hook.save!(validate: false)
    expect(json(hook, :settings).keys).to eq(['endpoint_url'])
    expect(Integrations::Hook.find(hook.id).settings['secret_key']).to eq('sk')
  end

  it 'encrypts the plain columns: API / widget HMAC tokens and API access tokens, still found by value' do
    widget = create(:channel_widget, account: account)
    expect(ActiveRecord::Encryption.encryptor.encrypted?(raw(widget, :hmac_token))).to be(true)
    expect(Channel::WebWidget.find_by(hmac_token: widget.hmac_token)).to eq(widget)

    token = create(:user, account: account).access_token
    expect(ActiveRecord::Encryption.encryptor.encrypted?(raw(token, :token))).to be(true)
    expect(AccessToken.find_by(token: token.token)).to eq(token)
  end

  it 'reports counts only, never a value' do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    rows = Tolzar::CredentialsTask.status
    expect(rows).to all(include(:model, :field))
    expect(rows.to_json).not_to include('test_key')
    expect(rows.select { |r| r.key?(:unreadable) }.sum { |r| r[:unreadable] }).to eq(0)
  end
end
