# Tolzar conversation summary on demand (round 4, E1; Shadow): POST tolzar/conversations/:display_id/summary asks the
# brain (POST /summary {account_id, conversation_id}) for a short summary and returns it to the staff member only.
# Nothing is written or sent: saving it as a private note is a separate staff click (the normal messages API).
# Anyone who may see the conversation (ConversationPolicy#show?); TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarConversationSummaryController < Api::V1::Accounts::BaseController
  MAX_LENGTH = 4000

  def create
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)

    conversation = Current.account.conversations.find_by!(display_id: params[:display_id])
    authorize conversation, :show?
    summary = brain_summary(conversation)
    return render(json: { ok: false, error: 'brain_unavailable' }, status: :bad_gateway) if summary.blank?

    render json: { ok: true, summary: summary }
  end

  private

  def brain_summary(conversation)
    res = Tolzar::BrainClient.post('/summary', { account_id: Current.account.id, conversation_id: conversation.display_id },
                                   account_id: Current.account.id)
    return nil unless res['status'] == 200

    res['summary'].is_a?(String) ? res['summary'].strip.first(MAX_LENGTH) : nil
  end
end
