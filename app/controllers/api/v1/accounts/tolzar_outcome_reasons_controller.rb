# Tolzar win/loss reasons (round 4, c95): GET tolzar/outcome_reasons?days=7|30|90 (Tolzar::OutcomeReasons).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarOutcomeReasonsController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    render json: { ok: true }.merge(Tolzar::OutcomeReasons.new(Current.account, days: params[:days]).report)
  end
end
