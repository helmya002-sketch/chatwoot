# Tolzar "What's new" (round 4, c90): GET tolzar/whats_new, this workspace's release notes (Tolzar::WhatsNew). Any member.
class Api::V1::Accounts::TolzarWhatsNewController < Api::V1::Accounts::BaseController
  def show
    render json: { ok: true, releases: Tolzar::WhatsNew.for(Current.account.id) }
  end
end
