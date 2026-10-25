# Tolzar: one raw respond.io webhook event (shadow mirror). See the migration.
class Tolzar::MirrorEvent < ApplicationRecord
  self.table_name = 'tolzar_mirror_events'

  scope :pending, -> { where(processed_at: nil) }
end
