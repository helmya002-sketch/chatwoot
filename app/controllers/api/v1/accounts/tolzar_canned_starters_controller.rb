# Tolzar saved-reply starter set (round 4, c93): POST tolzar/canned_starters adds the missing starter replies
# (Tolzar::CannedStarters). Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarCannedStartersController < Api::V1::Accounts::BaseController
  def create
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    render json: { ok: true, added: Tolzar::CannedStarters.add_missing!(Current.account) }
  end
end
