# Tolzar Results → Channels (round 4, c97): GET tolzar/channel_breakdown?days=7|30|90 (Tolzar::ChannelBreakdown).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarChannelBreakdownController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    render json: { ok: true }.merge(Tolzar::ChannelBreakdown.new(Current.account, days: params[:days]).report)
  end
end
