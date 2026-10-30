# Tolzar: a workspace's plan, trial and paid-until (billing v1, manual until XPay checkout). Workspaces that
# exist before this migration are "internal" (no trial, never paused), so nothing changes for them.
class CreateTolzarSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_subscriptions do |t|
      t.bigint :account_id, null: false
      t.string :plan, null: false, default: 'trial'
      t.datetime :trial_ends_at
      t.datetime :paid_until
      t.datetime :paused_at
      t.datetime :purge_after
      t.datetime :purged_at
      t.integer :seat_limit, null: false, default: 5
      t.string :currency, null: false, default: 'USD'
      t.string :provider
      t.string :customer_ref
      t.string :subscription_ref
      t.text :notes
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :tolzar_subscriptions, :account_id, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO tolzar_subscriptions (account_id, plan, seat_limit, currency, created_at, updated_at)
          SELECT id, 'internal', 1000, 'USD', NOW(), NOW() FROM accounts
        SQL
      end
    end
  end
end
