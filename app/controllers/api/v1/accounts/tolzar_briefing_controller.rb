# Tolzar briefing bar: GET tolzar/briefing?tz=<IANA zone>, what needs the signed-in member now (Tolzar::Briefing),
# limited to the conversations they may open. Any member; read-only. `tz` only decides where "today" ends.
class Api::V1::Accounts::TolzarBriefingController < Api::V1::Accounts::BaseController
  def show
    briefing = Tolzar::Briefing.new(Current.account, Current.user, time_zone: params[:tz].to_s.first(64))
    render json: { ok: true }.merge(briefing.report)
  end
end
