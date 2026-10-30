# Tolzar: the last 10 saved versions of each AI agent's instructions and settings (Tolzar::AgentVersion).
class CreateTolzarAgentVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_agent_versions do |t|
      t.bigint :account_id, null: false
      t.string :agent_id, null: false
      t.integer :version, null: false
      t.jsonb :payload, null: false, default: {}
      t.bigint :saved_by_id
      t.datetime :created_at, null: false
    end
    add_index :tolzar_agent_versions, [:account_id, :agent_id, :version], unique: true, name: 'index_tolzar_agent_versions_on_agent_version'
  end
end
