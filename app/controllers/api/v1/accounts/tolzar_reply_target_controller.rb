# Tolzar Results → Reply-time target (round 4, G2): GET tolzar/reply_target?days=7|30|90 (Tolzar::ReplyTarget).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise). The target is the brain's SLA when it
# answers and the SLA is on; brain down or SLA off = the default target, labelled as such.
class Api::V1::Accounts::TolzarReplyTargetController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    sla = Tolzar::BrainClient.get("/sla?account_id=#{Current.account.id}", account_id: Current.account.id)['config']
    render json: { ok: true }.merge(Tolzar::ReplyTarget.new(Current.account, days: params[:days], sla: sla).report)
  end
end
