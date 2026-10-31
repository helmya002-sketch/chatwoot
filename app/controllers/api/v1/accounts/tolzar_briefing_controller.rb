# Tolzar briefing bar: GET tolzar/briefing, what needs the signed-in member now (Tolzar::Briefing), limited to the
# conversations they may open. Any member; read-only.
class Api::V1::Accounts::TolzarBriefingController < Api::V1::Accounts::BaseController
  def show
    render json: { ok: true }.merge(Tolzar::Briefing.new(Current.account, Current.user).report)
  end
end
