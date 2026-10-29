# Tolzar: a workspace's own Meta app (Facebook Messenger, Instagram DMs and comments), and the
# listen-only flag on Facebook Page and Instagram inboxes (Tolzar::ListenOnly). The secret and the
# verify token are encrypted by the model; the webhook token names neither the workspace nor the app.
class CreateTolzarMetaApps < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_meta_apps do |t|
      t.references :account, null: false, index: { unique: true }
      t.string :app_id, null: false
      t.text :app_secret, null: false
      t.text :verify_token, null: false
      t.string :webhook_token, null: false
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :tolzar_meta_apps, :webhook_token, unique: true

    add_column :channel_facebook_pages, :tolzar_listen_only, :boolean, default: false, null: false
    add_column :channel_instagram, :tolzar_listen_only, :boolean, default: false, null: false
  end
end
