# Tolzar W9 follow-up (Oracle 31 Oct): Super Admin's app credentials (FB_APP_SECRET, WHATSAPP_APP_SECRET,
# TIKTOK_APP_SECRET, SLACK_CLIENT_SECRET, … any name that reads as a secret) are stored encrypted in their own
# text column, `tolzar_encrypted_value`, instead of in the plain YAML `serialized_value`. `value` / `value=` read
# and write the encrypted column for those names, so GlobalConfig, ConfigLoader and Super Admin keep working
# unchanged; a row written before this keeps its plain value readable until `rails tolzar:encrypt_credentials`
# moves it. Other configs (flags, URLs, feature lists) stay as they are.
module Tolzar::EncryptedInstallationConfig
  SECRET_NAME = /(SECRET|PASSWORD|API_KEY|_TOKEN|PRIVATE_KEY|IDENTIFIER_HASH)/

  def self.secret_name?(name)
    name.to_s.match?(SECRET_NAME)
  end

  def value
    return super unless tolzar_encrypts_value?
    return super if tolzar_encrypted_value.blank?

    JSON.parse(tolzar_encrypted_value)['v']
  rescue JSON::ParserError
    super
  end

  def value=(value_to_assign)
    return super unless tolzar_encrypts_value?

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
