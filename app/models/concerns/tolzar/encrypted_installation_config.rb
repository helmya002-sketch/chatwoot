# Tolzar W9 follow-up (Oracle 31 Oct): Super Admin's app credentials (FB_APP_SECRET, WHATSAPP_APP_SECRET,
# TIKTOK_APP_SECRET, SLACK_CLIENT_SECRET, … any name that reads as a secret) are stored encrypted in their own
# text column, `tolzar_encrypted_value`, instead of in the plain YAML `serialized_value`. `value` / `value=` read
# and write the encrypted column for those names, so GlobalConfig, ConfigLoader and Super Admin keep working
# unchanged; a row written before this keeps its plain value readable until `rails tolzar:encrypt_credentials`
# moves it. Other configs (flags, URLs, feature lists) stay as they are.
module Tolzar::EncryptedInstallationConfig
  # VAPID_KEYS holds the web-push private key next to the public one (round 4, c63: the PWA's push).
  SECRET_NAME = /(SECRET|PASSWORD|API_KEY|_TOKEN|PRIVATE_KEY|IDENTIFIER_HASH|\AVAPID_KEYS\z)/
  # Settings about a token, not a token (WIDGET_TOKEN_EXPIRY is a number of days): never treated as secrets.
  NOT_SECRET = /(_EXPIRY|_TTL|_TIMEOUT|_LENGTH|_ENABLED)\z/

  def self.secret_name?(name)
    name.to_s.match?(SECRET_NAME) && !name.to_s.match?(NOT_SECRET)
  end

  # Reads the encrypted column whenever it holds a value (also for a name no longer treated as secret, until its
  # next write moves it back to the plain column).
  def value
    return super unless has_attribute?(:tolzar_encrypted_value)
    return super if tolzar_encrypted_value.blank?

    JSON.parse(tolzar_encrypted_value)['v']
  rescue JSON::ParserError
    super
  end

  def value=(value_to_assign)
    unless tolzar_encrypts_value?
      self.tolzar_encrypted_value = nil if has_attribute?(:tolzar_encrypted_value)
      return super
    end

    self.tolzar_encrypted_value = { v: value_to_assign }.to_json
    super(nil)
  end

  # True while this secret's value still sits in the plain column.
  def tolzar_value_pending?
    tolzar_encrypts_value? && serialized_value.to_h.with_indifferent_access[:value].present?
  end

  private

  def tolzar_encrypts_value?
    has_attribute?(:tolzar_encrypted_value) && Tolzar::EncryptedInstallationConfig.secret_name?(name)
  end
end
