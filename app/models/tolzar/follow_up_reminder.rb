# Tolzar follow-up reminder (round 4, E4), for TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces: "remind me in 1 / 2 / 3 days
# if the customer doesn't answer", one per person per conversation. Tolzar::FollowUpRemindersJob (every 15 min) turns a
# due one into an in-app notification for that person, unless the customer wrote after set_at; a customer message
# removes the conversation's reminders at once (Tolzar::FollowUpRemindersListener). Nothing is ever sent to the customer.
class Tolzar::FollowUpReminder < ApplicationRecord
  self.table_name = 'tolzar_follow_up_reminders'

  DAYS = [1, 2, 3].freeze
  NOTIFICATION_TYPE = 'tolzar_follow_up_due'.freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  validates :due_at, :set_at, presence: true

  scope :due, ->(at = Time.current) { where(due_at: ..at) }

  def self.enabled_account_ids
    ENV.fetch('TOLZAR_INBOX_TOOLS_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  # Sets (or moves) this person's reminder on the conversation; days must be 1, 2 or 3.
  def self.remind!(conversation, user, days)
    raise ArgumentError, 'days' unless DAYS.include?(days)

    now = Time.current
    reminder = find_or_initialize_by(conversation_id: conversation.id, user_id: user.id)
    reminder.update!(account_id: conversation.account_id, due_at: now + days.days, set_at: now)
    reminder
  end

  # True when the customer has written in the conversation since the reminder was set.
  def customer_answered?
    conversation.messages.incoming.where(created_at: set_at..).exists?
  end

  def view
    { due_at: due_at.iso8601, set_at: set_at.iso8601 }
  end
end
