# Tolzar W9 rollback: undo what `rails tolzar:encrypt_credentials` did for the fields this release added, so the
# previous release (which reads them as plain text) works again. Run it BEFORE deploying the previous image:
#   rails tolzar:decrypt_credentials
# Upstream's own encrypted fields are left as they are (the previous release reads those too). Counts only.
module Tolzar::CredentialsRollback
  module_function

  def run!
    counts = Hash.new(0)
    ActiveRecord::Base.transaction do
      Tolzar::EncryptedCredentials::COLUMNS.each do |name, attrs|
        counts[name] += plain_columns(name.constantize, attrs.keys)
      end
      Tolzar::EncryptedCredentials::JSON_SECRETS.each_key { |name| counts["#{name} json"] += json_back(name.constantize) }
      counts['InstallationConfig'] += installation_back
    end
    counts
  end

  def plain_columns(klass, attrs)
    attrs = attrs.select { |attr| Array(klass.encrypted_attributes).include?(attr) }
    return 0 if attrs.empty?

    klass.unscoped.find_each.sum do |record|
      values = attrs.index_with { |attr| record.public_send(attr) }
      ActiveRecord::Encryption.without_encryption { record.update_columns(values) } # rubocop:disable Rails/SkipsModelValidations
      1
    end
  end

  def installation_back
    return 0 unless InstallationConfig.include?(Tolzar::EncryptedInstallationConfig)

    InstallationConfig.unscoped.find_each.sum do |config|
      next 0 if config.tolzar_encrypted_value.blank?

      plain = { value: config.value }.with_indifferent_access
      config.update_columns(serialized_value: plain, tolzar_encrypted_value: nil) # rubocop:disable Rails/SkipsModelValidations
      1
    end
  end

  def json_back(klass)
    return 0 unless klass.include?(Tolzar::EncryptedJsonSecrets)

    column = klass.tolzar_json_secrets_spec[:column]
    klass.unscoped.find_each.sum do |record|
      next 0 if record.tolzar_secrets.blank?

      # The JSON hash already carries the secrets in memory (merged after load).
      record.update_columns(column => record.public_send(column), tolzar_secrets: nil) # rubocop:disable Rails/SkipsModelValidations
      1
    end
  end
end
