# Tolzar search within a contact (round 4, E5): GET tolzar/contacts/:contact_id/search?q= (Tolzar::ContactSearch).
# Anyone in the workspace who may see the contact; hits only from conversations they may see. q is 2-100 characters
# (422 otherwise). TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarContactSearchController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)

    contact = Current.account.contacts.find(params[:contact_id])
    authorize contact, :show?
    return render(json: { ok: false, error: 'query_length' }, status: :unprocessable_entity) unless Tolzar::ContactSearch.valid_query?(params[:q])

    render json: { ok: true, results: Tolzar::ContactSearch.new(Current.account, contact, Current.user, params[:q]).results }
  end
end
