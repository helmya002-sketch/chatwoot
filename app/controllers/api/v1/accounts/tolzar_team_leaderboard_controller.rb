# Tolzar Results → Team (round 4, c96): GET tolzar/team_leaderboard?days=7|30|90 (Tolzar::TeamLeaderboard).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarTeamLeaderboardController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    render json: { ok: true }.merge(Tolzar::TeamLeaderboard.new(Current.account, days: params[:days]).report)
  end
end
