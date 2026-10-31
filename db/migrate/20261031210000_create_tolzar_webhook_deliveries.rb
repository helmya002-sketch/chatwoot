# Tolzar webhook delivery log (round 4, H2): the last 50 deliveries per workspace webhook (time, event, HTTP status,
# duration). Never the payload, the URL or the secret. Rows go with their webhook.
class CreateTolzarWebhookDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_webhook_deliveries do |t|
      t.bigint :account_id, null: false
      t.bigint :webhook_id, null: false
      t.string :event, limit: 64
      t.integer :status
      t.boolean :ok, null: false, default: false
      t.string :error, limit: 32
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end
    add_index :tolzar_webhook_deliveries, [:webhook_id, :id]
    add_foreign_key :tolzar_webhook_deliveries, :webhooks, on_delete: :cascade
  end
end
