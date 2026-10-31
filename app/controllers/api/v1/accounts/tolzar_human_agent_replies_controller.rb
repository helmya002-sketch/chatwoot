# Tolzar Meta HUMAN_AGENT audit (round 4, c77): GET tolzar/human_agent_replies, the newest 200 Messenger / Instagram
# replies sent with Meta's Human Agent tag (Tolzar::MetaHumanAgent.record!): when, by whom, which conversation and
# inbox. Administrators; read-only. It lists people only: the AI and bots never use the tag.
class Api::V1::Accounts::TolzarHumanAgentRepliesController < Api::V1::Accounts::BaseController
  LIMIT = 200

  before_action :ensure_admin

  def index
    rows = Message.where(account_id: Current.account.id).where("messages.content_attributes->>'tolzar_human_agent_tag' = 'true'")
                  .includes(:conversation, :inbox, :sender).order(created_at: :desc).limit(LIMIT)
    render json: { ok: true, replies: rows.map { |m| view(m) } }
  end

  private

  def view(message)
    { id: message.id, at: message.created_at.utc.iso8601, sender: message.sender&.name.to_s, tag: 'HUMAN_AGENT',
      conversation_id: message.conversation&.display_id, inbox: message.inbox&.name.to_s, status: message.status }
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end
end
