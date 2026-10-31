# Tolzar W9: encrypt every stored channel / integration credential and prove it can still be read.
#   rails tolzar:credentials_status     counts only, per model and field: rows, encrypted, still plaintext,
#                                        unreadable (decrypt failed). Never a value.
#   rails tolzar:encrypt_credentials    encrypts the plaintext rows (Active Record `encrypt`) and moves the
#                                        JSON-held keys into `tolzar_secrets`; then prints the status.
#   rails tolzar:decrypt_credentials    rollback only: the reverse, for the fields this release added
#                                        (Tolzar::CredentialsRollback), before deploying the previous image.
# Both need the ACTIVE_RECORD_ENCRYPTION_* keys (Chatwoot.encryption_configured?); without them they stop.
# The work is Tolzar::CredentialsTask (app/services/tolzar/credentials_task.rb).

namespace :tolzar do
  desc 'Counts only: per credential field, rows encrypted / plaintext / unreadable'
  task credentials_status: :environment do
    Tolzar::CredentialsTask.require_keys!
    Tolzar::CredentialsTask.status.each { |row| puts row.to_json }
  end

  desc 'Encrypt every plaintext credential and move JSON-held keys into tolzar_secrets'
  task encrypt_credentials: :environment do
    Tolzar::CredentialsTask.require_keys!
    Tolzar::CredentialsTask.encrypt!
    Tolzar::CredentialsTask.status.each { |row| puts row.to_json }
  end

  desc 'Rollback: turn the fields this release encrypted back into plain text (run before deploying the previous image)'
  task decrypt_credentials: :environment do
    Tolzar::CredentialsTask.require_keys!
    Tolzar::CredentialsRollback.run!.each { |name, count| puts({ model: name, rows_written: count }.to_json) }
  end
end
