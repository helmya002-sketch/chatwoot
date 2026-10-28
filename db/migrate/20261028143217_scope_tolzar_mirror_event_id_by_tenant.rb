# Tolzar: respond.io event ids are only unique within one respond.io workspace, so the mirror's
# idempotency key is (tenant, event_id): the same id from another tenant (account) is another event.
class ScopeTolzarMirrorEventIdByTenant < ActiveRecord::Migration[7.1]
  def change
    remove_index :tolzar_mirror_events, :event_id, unique: true
    add_index :tolzar_mirror_events, [:tenant, :event_id], unique: true
  end
end
