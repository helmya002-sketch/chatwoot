# == Schema Information
#
# Table name: agent_bots
#
#  id           :bigint           not null, primary key
#  bot_config   :jsonb
#  bot_type     :integer          default("webhook")
#  description  :string
#  name         :string
#  outgoing_url :string
#  secret       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint
#
# Indexes
#
#  index_agent_bots_on_account_id  (account_id)
#

class AgentBot < ApplicationRecord
  include AccessTokenable
  include Avatarable

  include WebhookSecretable

  scope :accessible_to, lambda { |account|
    account_id = account&.id
    where(account_id: [nil, account_id])
  }

  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :agent_bot_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :platform_app_permissibles, as: :permissible, dependent: :destroy
  has_many :assigned_conversations, class_name: 'Conversation',
                                    foreign_key: :assignee_agent_bot_id,
                                    dependent: :nullify,
                                    as: :ai_assignee,
                                    inverse_of: :ai_assignee
  belongs_to :account, optional: true
  enum bot_type: { webhook: 0 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  def available_name
    name
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url || inbox&.avatar_url,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'agent_bot'
    }
  end

  def system_bot?
    account.nil?
  end

  # Tolzar: this bot is the Tolzar brain running in shadow. It only writes private "Tolzar would..."
  # notes and never replies, so conversations in its inboxes must not wait in Pending for a bot hand-off
  # that never comes. Detected by the bot's outgoing_url host being the brain's host
  # (Tolzar::BrainClient.brain_host, from TOLZAR_BRAIN_URL), or explicitly by bot_config['tolzar_shadow'].
  def tolzar_shadow?
    config = bot_config.is_a?(Hash) ? bot_config : {}
    return true if ActiveModel::Type::Boolean.new.cast(config['tolzar_shadow'])

    host = URI.parse(outgoing_url.to_s.strip).host
    host.present? && host.casecmp?(Tolzar::BrainClient.brain_host.to_s)
  rescue URI::InvalidURIError
    false
  end
end

AgentBot.include_mod_with('Audit::AgentBot')
