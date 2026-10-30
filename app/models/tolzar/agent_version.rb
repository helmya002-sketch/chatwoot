# Tolzar: the last KEEP saved versions of each AI agent (its instructions and settings, as sent to the
# brain), so an administrator can see what changed and when. Written by the proxy after the brain
# accepted a save (Api::V1::Accounts::TolzarController#agent_save); the brain stays the agent's store.
class Tolzar::AgentVersion < ApplicationRecord
  self.table_name = 'tolzar_agent_versions'

  KEEP = 10

  belongs_to :account
  belongs_to :saved_by, class_name: 'User', optional: true

  validates :agent_id, presence: true, length: { maximum: 80 }
  validates :version, presence: true, uniqueness: { scope: %i[account_id agent_id] }

  scope :for_agent, ->(account, agent_id) { where(account: account, agent_id: agent_id) }
  scope :newest_first, -> { order(version: :desc) }

  # The next version of this agent, then only the newest KEEP are kept.
  def self.record!(account:, agent_id:, payload:, user:)
    versions = for_agent(account, agent_id)
    transaction do
      created = versions.create!(version: versions.maximum(:version).to_i + 1, payload: payload, saved_by: user)
      versions.newest_first.offset(KEEP).destroy_all
      created
    end
  end

  def view
    { version: version, payload: payload, saved_by: saved_by_id, saved_by_name: saved_by&.name, created_at: created_at }
  end
end
