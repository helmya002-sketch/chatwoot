# Tolzar W9 (Oracle 31 Oct, "encrypted per-workspace credentials" made literally true): upstream keeps some
# credentials inside a JSON settings column (WhatsApp Cloud's provider_config api_key and registration PIN,
# the e-mail OAuth tokens, SMS API keys, LeadSquared keys in a hook's settings). A JSON column cannot be
# encrypted as a whole (lookups query its other keys), so the named keys live in their own encrypted text
# column, `tolzar_secrets`, and are merged back into the JSON hash in memory:
#   - after load (and after save) the JSON hash carries the secrets again, so every reader
#     (`provider_config['api_key']`, about 20 call sites) and every in-place write keeps working unchanged;
#   - before save the named keys are taken out of the JSON and written, encrypted, to `tolzar_secrets`.
# A key absent from the JSON at save time is removed from `tolzar_secrets` too (the same as upstream, where
# dropping it from the hash dropped it from the row). Rows not yet moved keep working: their secrets are still in
# the JSON until `rails tolzar:encrypt_credentials` (or any save) moves them.
module Tolzar::EncryptedJsonSecrets
  extend ActiveSupport::Concern

  included do
    class_attribute :tolzar_json_secrets_spec, instance_writer: false
  end

  class_methods do
    def tolzar_json_secrets(column, keys)
      self.tolzar_json_secrets_spec = { column: column.to_s, keys: keys.map(&:to_s).freeze }.freeze
      encrypts :tolzar_secrets if Chatwoot.encryption_configured?
      after_initialize :tolzar_merge_json_secrets
      before_save :tolzar_split_json_secrets
      after_save :tolzar_merge_json_secrets
    end
  end

  # True while any named key is still stored in the JSON column itself (not moved yet).
  def tolzar_json_secrets_pending?
    raw = attribute_in_database(tolzar_json_secrets_spec[:column])
    raw.is_a?(Hash) && raw.stringify_keys.slice(*tolzar_json_secrets_spec[:keys]).compact.any?
  end

  # The move for `rails tolzar:encrypt_credentials`: written straight to the row (no validations, no callbacks: a
  # live channel whose provider check would fail, e.g. an expired token, must still be moved, and the task must
  # not call the provider per channel). Returns true when the row reads back as moved.
  def tolzar_move_json_secrets!
    return true unless tolzar_json_secrets_ready? && tolzar_json_secrets_pending?

    column = tolzar_json_secrets_spec[:column]
    keys = tolzar_json_secrets_spec[:keys]
    raw = attribute_in_database(column).to_h.stringify_keys
    secrets = tolzar_stored_secrets.merge(raw.slice(*keys).compact)
    update_columns(column => raw.except(*keys), tolzar_secrets: secrets.to_json) # rubocop:disable Rails/SkipsModelValidations
    !self.class.unscoped.find(id).tolzar_json_secrets_pending?
  end

  private

  def tolzar_json_secrets_ready?
    spec = tolzar_json_secrets_spec
    spec && has_attribute?(:tolzar_secrets) && has_attribute?(spec[:column])
  end

  def tolzar_stored_secrets
    parsed = JSON.parse(tolzar_secrets.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def tolzar_merge_json_secrets
    return unless tolzar_json_secrets_ready?

    column = tolzar_json_secrets_spec[:column]
    stored = tolzar_stored_secrets
    return if stored.empty?

    current = (self[column] || {}).to_h.stringify_keys
    dirty = attribute_changed?(column)
    self[column] = stored.merge(current) # a value set in memory wins over the stored one
    clear_attribute_changes([column]) unless dirty
  end

  def tolzar_split_json_secrets
    return unless tolzar_json_secrets_ready?

    column = tolzar_json_secrets_spec[:column]
    keys = tolzar_json_secrets_spec[:keys]
    current = (self[column] || {}).to_h.stringify_keys
    secrets = current.slice(*keys).compact
    self[column] = current.except(*keys)
    self.tolzar_secrets = secrets.empty? ? nil : secrets.to_json
  end
end
