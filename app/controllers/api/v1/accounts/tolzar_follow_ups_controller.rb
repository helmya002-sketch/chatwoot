# Tolzar follow-up reminders (round 4, E4): GET / POST {days: 1|2|3} / DELETE tolzar/conversations/:display_id/follow_up
# reads, sets or cancels the signed-in person's own "remind me if the customer doesn't answer" (Tolzar::FollowUpReminder).
# Anyone who may see the conversation (ConversationPolicy#show?), for themselves only; TOLZAR_INBOX_TOOLS_ACCOUNTS
# workspaces (404 otherwise).
class Api::V1::Accounts::TolzarFollowUpsController < Api::V1::Accounts::BaseController
  before_action :check_switch
  before_action :conversation

  def show
    render json: { ok: true, reminder: reminder&.view }
  end

  def create
    days = params[:days].to_i
    return render(json: { ok: false, error: 'days' }, status: :unprocessable_entity) unless Tolzar::FollowUpReminder::DAYS.include?(days)

    render json: { ok: true, reminder: Tolzar::FollowUpReminder.remind!(@conversation, Current.user, days).view }
  end

  def destroy
    reminder&.destroy!
    render json: { ok: true, reminder: nil }
  end

  private

  def check_switch
    head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
  end

  def conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:display_id])
    authorize @conversation, :show?
  end

  def reminder
    Tolzar::FollowUpReminder.find_by(conversation_id: @conversation.id, user_id: Current.user.id)
  end
end
