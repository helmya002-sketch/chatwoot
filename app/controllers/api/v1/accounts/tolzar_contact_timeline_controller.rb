# Tolzar contact timeline (round 4, c99): GET tolzar/contacts/:contact_id/timeline (Tolzar::ContactTimeline).
# Anyone in the workspace who may see contacts; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarContactTimelineController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)

    contact = Current.account.contacts.find(params[:contact_id])
    authorize contact, :show?
    render json: { ok: true, events: Tolzar::ContactTimeline.new(Current.account, contact, Current.user).events }
  end
end
