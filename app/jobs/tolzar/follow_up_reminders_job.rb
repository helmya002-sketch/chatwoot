# Tolzar follow-up reminders (round 4, E4): every 15 minutes, each due reminder in a TOLZAR_INBOX_TOOLS_ACCOUNTS
# workspace becomes an in-app notification for its person (NotificationBuilder, which also checks they may still see
# the conversation), unless the customer wrote after it was set. Either way the reminder is then done and removed.
# One reminder failing never stops the others.
class Tolzar::FollowUpRemindersJob < ApplicationJob
  queue_as :low

  def perform
    ids = Tolzar::FollowUpReminder.enabled_account_ids
    return if ids.empty?

    Tolzar::FollowUpReminder.where(account_id: ids).due.includes(:conversation, :user, :account).find_each do |reminder|
      notify(reminder)
    rescue StandardError => e
      Rails.logger.error("[Tolzar] follow-up reminder #{reminder.id} failed: #{e.class}")
    end
  end

  private

  def notify(reminder)
    if reminder.conversation && reminder.user && !reminder.customer_answered?
      NotificationBuilder.new(notification_type: Tolzar::FollowUpReminder::NOTIFICATION_TYPE, user: reminder.user,
                              account: reminder.account, primary_actor: reminder.conversation).perform
    end
    reminder.destroy!
  end
end
