# Tolzar Control Center: one row per super-admin change (Tolzar::SuperAdminAudit). Names of the fields sent, never
# their values, so no secret can land here.
class CreateTolzarSuperAdminAudits < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_super_admin_audits do |t|
      t.bigint :super_admin_id
      t.string :email
      t.string :controller, null: false
      t.string :action, null: false
      t.string :http_method, null: false
      t.string :path, null: false
      t.string :record_id
      t.jsonb :fields, null: false, default: []
      t.integer :status
      t.string :ip
      t.datetime :created_at, null: false
    end
    add_index :tolzar_super_admin_audits, :created_at
    add_index :tolzar_super_admin_audits, :super_admin_id
  end
end
