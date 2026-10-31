# Tolzar W9: the work behind `rails tolzar:credentials_status` and `rails tolzar:encrypt_credentials`
# (lib/tasks/tolzar_encrypted_credentials.rake). Counts only, never a value.
module Tolzar::CredentialsTask
  module_function

  def models
    names = %w[Channel::Whatsapp Channel::Email Channel::FacebookPage Channel::Instagram Channel::Line
               Channel::Telegram Channel::Tiktok Channel::TwilioSms Channel::TwitterProfile Channel::Api
               Channel::WebWidget Channel::Sms Webhook AgentBot Integrations::Hook DataImport AccessToken
               Tolzar::MetaApp User InstallationConfig]
    names.filter_map(&:safe_constantize)
  end

  def encrypted_fields(klass)
    Array(klass.encrypted_attributes).map(&:to_s)
  end

  def ciphertext?(raw)
    raw.is_a?(String) && ActiveRecord::Encryption.encryptor.encrypted?(raw)
  end

  def status
    models.flat_map { |klass| encrypted_fields(klass).map { |field| field_status(klass, field) } } + json_status +
      [installation_status]
  end

  def field_status(klass, field)
    counts = { model: klass.name, field: field, rows: 0, encrypted: 0, plaintext: 0, empty: 0, unreadable: 0 }
    klass.unscoped.find_each do |record|
      counts[:rows] += 1
      raw = record.read_attribute_before_type_cast(field)
      next counts[:empty] += 1 if raw.blank?

      counts[ciphertext?(raw) ? :encrypted : :plaintext] += 1
      counts[:unreadable] += 1 unless readable?(record, field)
    end
    counts
  end

  def readable?(record, field)
    record.public_send(field)
    true
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def installation_status
    rows = InstallationConfig.unscoped.select { |c| Tolzar::EncryptedInstallationConfig.secret_name?(c.name) }
    { model: 'InstallationConfig', field: 'secret values', rows: rows.size, value_pending: rows.count(&:tolzar_value_pending?) }
  end

  def json_status
    models.select { |k| k.include?(Tolzar::EncryptedJsonSecrets) }.map do |klass|
      pending = klass.unscoped.find_each.count(&:tolzar_json_secrets_pending?)
      { model: klass.name, field: "#{klass.tolzar_json_secrets_spec[:column]} keys", rows: klass.unscoped.count,
        json_pending: pending }
    end
  end

  def encrypt!
    models.each do |klass|
      next if encrypted_fields(klass).empty? && !klass.include?(Tolzar::EncryptedJsonSecrets)

      klass.unscoped.find_each do |record|
        record.encrypt if encrypted_fields(klass).any?
        record.update!(value: record.value) if record.is_a?(InstallationConfig) && record.tolzar_value_pending?
        next unless klass.include?(Tolzar::EncryptedJsonSecrets)

        Rails.logger.warn("[tolzar] credentials: #{klass.name} #{record.id} not moved") unless record.tolzar_move_json_secrets!
      end
    end
  end

  def require_keys!
    abort 'ACTIVE_RECORD_ENCRYPTION_* keys are not configured: nothing can be encrypted' unless Chatwoot.encryption_configured?
  end
end
