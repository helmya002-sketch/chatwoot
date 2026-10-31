# Tolzar W9: encrypt every stored channel / integration credential (Tolzar::EncryptedCredentials in
# app/services/tolzar/encrypted_credentials.rb). In to_prepare: the Tolzar namespace is autoloaded by then (a
# top-level `module Tolzar::...` here broke the boot, c16 key run 31 Oct), and the encrypts declarations are
# re-applied after every code reload.
Rails.application.config.to_prepare { Tolzar::EncryptedCredentials.apply! }
