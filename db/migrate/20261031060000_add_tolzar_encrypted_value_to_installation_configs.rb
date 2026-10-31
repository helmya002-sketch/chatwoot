# Tolzar W9 follow-up: an encrypted text column for Super Admin's app secrets (Tolzar::EncryptedInstallationConfig).
# A nullable column only; `rails tolzar:encrypt_credentials` moves the existing values after the deploy.
class AddTolzarEncryptedValueToInstallationConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :installation_configs, :tolzar_encrypted_value, :text
  end
end
