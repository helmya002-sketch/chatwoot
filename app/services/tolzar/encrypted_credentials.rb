# Tolzar W9 (Oracle 31 Oct): every channel and integration credential stored in the database is encrypted at
# rest with Active Record encryption (config/application.rb: ACTIVE_RECORD_ENCRYPTION_* keys; legacy plaintext
# rows stay readable through support_unencrypted_data / extend_queries until `rails tolzar:encrypt_credentials`
# has encrypted them). Upstream already encrypts most of them; this adds the rest, in one place, without editing
# the upstream models. Applied by config/initializers/zz_tolzar_encrypted_credentials.rb (to_prepare, so the
# Tolzar namespace is autoloaded and the declarations survive code reloads):
#   columns   Channel::TwilioSms#api_key_secret; Channel::Api#hmac_token and Channel::WebWidget#hmac_token
#             (the identity-validation secrets; deterministic, they are unique and may be looked up);
#             AccessToken#token (the user / bot API tokens; deterministic: login looks them up by value)
#   JSON keys Tolzar::EncryptedJsonSecrets (the keys move to the encrypted `tolzar_secrets` column)
module Tolzar::EncryptedCredentials
  COLUMNS = {
    'Channel::TwilioSms' => { api_key_secret: {} },
    'Channel::Api' => { hmac_token: { deterministic: true } },
    'Channel::WebWidget' => { hmac_token: { deterministic: true } },
    'AccessToken' => { token: { deterministic: true } }
  }.freeze

  JSON_SECRETS = {
    'Channel::Whatsapp' => [:provider_config, %w[api_key verification_pin webhook_verify_token app_secret]],
    'Channel::Email' => [:provider_config, %w[access_token refresh_token]],
    'Channel::Sms' => [:provider_config, %w[api_key api_secret]],
    'Channel::TwilioSms' => [:provider_config, %w[webhook_auth_token]],
    'Integrations::Hook' => [:settings, %w[access_key secret_key api_key token password]]
  }.freeze

  module_function

  def apply!
    return unless Chatwoot.encryption_configured?

    COLUMNS.each do |name, attrs|
      klass = name.constantize
      attrs.each do |attr, options|
        next if klass.encrypted_attributes&.include?(attr)

        klass.encrypts(attr, **options)
      end
    end
    JSON_SECRETS.each do |name, (column, keys)|
      klass = name.constantize
      next if klass.include?(Tolzar::EncryptedJsonSecrets)

      klass.include(Tolzar::EncryptedJsonSecrets)
      klass.tolzar_json_secrets(column, keys)
    end
  end
end
