# Tolzar follow-up reminders (round 4, E4): when the customer writes (an incoming message), the conversation's
# "remind me if the customer doesn't answer" reminders are no longer needed, so they go. Only for
# TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; everything else: nothing happens.
class Tolzar::FollowUpRemindersListener < BaseListener
  include Singleton

  def message_created(event)
    message = event.data[:message]
    return unless message&.incoming?
    return unless Tolzar::CannedStarters.enabled?(message.account_id)

    Tolzar::FollowUpReminder.where(conversation_id: message.conversation_id).delete_all
  end
end
