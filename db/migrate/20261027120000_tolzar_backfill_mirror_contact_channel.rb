# Tolzar: mirror contacts predate the projector stamping `rio_channel_source` on the contact.
# Copy it from each contact's most recent mirror conversation (where the projector has always
# stored it) so the Contacts page shows WhatsApp / email / ... instead of the API inbox.
# Idempotent; touches only contacts whose conversations carry the key.
# Cosmetic only, so it must never block boot (`db:chatwoot_prepare && rails s`): it runs outside
# a transaction and logs instead of raising.
class TolzarBackfillMirrorContactChannel < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      UPDATE contacts c
      SET additional_attributes = COALESCE(c.additional_attributes, '{}'::jsonb)
            || jsonb_build_object('rio_channel_source', latest.src)
      FROM (
        SELECT DISTINCT ON (contact_id) contact_id, additional_attributes->>'rio_channel_source' AS src
        FROM conversations
        WHERE additional_attributes->>'rio_channel_source' IS NOT NULL
        ORDER BY contact_id, last_activity_at DESC NULLS LAST, id DESC
      ) latest
      WHERE c.id = latest.contact_id
        AND (c.additional_attributes->>'rio_channel_source') IS DISTINCT FROM latest.src
    SQL
  rescue StandardError => e
    Rails.logger.warn("[tolzar] mirror contact channel backfill skipped: #{e.class}: #{e.message}")
  end

  def down
    # Data-only backfill; the key is harmless to keep.
  end
end
