# Tolzar: raw respond.io webhook events for the shadow mirror (Aquarius + Xplorer).
# The controller only verifies + stores + enqueues (respond.io needs a 200 in 5s);
# the projector job reads these rows. Raw payloads are pruned after 180 days.
class CreateTolzarMirrorEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_mirror_events do |t|
      t.string   :tenant, null: false            # aquarius | xplorer
      t.string   :event_id, null: false          # respond.io event_id (idempotency key)
      t.string   :event_type                      # message.received | message.sent | ...
      t.bigint   :rio_contact_id
      t.bigint   :rio_message_id
      t.jsonb    :payload, null: false, default: {}
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.string   :error
      t.timestamps
    end
    add_index :tolzar_mirror_events, :event_id, unique: true
    add_index :tolzar_mirror_events, [:tenant, :received_at]
    add_index :tolzar_mirror_events, :processed_at
  end
end
