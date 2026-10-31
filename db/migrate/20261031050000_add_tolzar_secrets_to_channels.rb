# Tolzar W9: an encrypted text column for the credentials upstream keeps inside a JSON settings column
# (Tolzar::EncryptedJsonSecrets). Adding nullable columns only: nothing is moved here; the move is
# `rails tolzar:encrypt_credentials`, run after the deploy (old rows stay readable until then).
class AddTolzarSecretsToChannels < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :tolzar_secrets, :text
    add_column :channel_email, :tolzar_secrets, :text
    add_column :channel_sms, :tolzar_secrets, :text
    add_column :channel_twilio_sms, :tolzar_secrets, :text
    add_column :integrations_hooks, :tolzar_secrets, :text
  end
end
