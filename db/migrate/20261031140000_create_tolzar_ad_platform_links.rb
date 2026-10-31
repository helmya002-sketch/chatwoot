# Tolzar ad-platform link (TikTok plan row 7): a workspace's opt-in to send pipeline outcomes back to its ad
# account (TikTok's CRM events), so ads optimise for real customers. The token is encrypted and write-only.
class CreateTolzarAdPlatformLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_ad_platform_links do |t|
      t.bigint :account_id, null: false
      t.string :platform, null: false
      t.string :event_set_id
      t.text :token
      t.jsonb :stage_events, null: false, default: {}
      t.boolean :enabled, null: false, default: false
      t.integer :sent_count, null: false, default: 0
      t.datetime :last_sent_at
      t.string :last_error
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :tolzar_ad_platform_links, [:account_id, :platform], unique: true
  end
end
