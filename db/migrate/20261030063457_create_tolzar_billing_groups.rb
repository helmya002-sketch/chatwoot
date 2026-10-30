# Tolzar: a billing group (Business plan) shares one monthly AI-reply allowance between up to 5
# workspaces. The brain keeps the members, the allowance, the timezone and the counters
# (billing_groups.py); this row is the fork's side: who owns it, the plan, and the provider-neutral
# subscription reference billing v1 fills in (left empty until then). No database foreign keys.
class CreateTolzarBillingGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_billing_groups do |t|
      t.bigint :brain_group_id, null: false
      t.bigint :owner_user_id
      t.string :plan, null: false, default: 'business'
      t.string :provider
      t.string :customer_ref
      t.string :subscription_ref
      t.timestamps
    end
    add_index :tolzar_billing_groups, :brain_group_id, unique: true
    add_index :tolzar_billing_groups, :owner_user_id

    add_column :accounts, :tolzar_billing_group_id, :bigint
    add_index :accounts, :tolzar_billing_group_id
  end
end
