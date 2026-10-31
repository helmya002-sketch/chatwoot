# Tolzar Results → Customer ratings (round 4, G1): GET tolzar/customer_ratings?days=7|30|90 (Tolzar::CustomerRatings).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarCustomerRatingsController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    render json: { ok: true }.merge(Tolzar::CustomerRatings.new(Current.account, days: params[:days]).report)
  end
end
