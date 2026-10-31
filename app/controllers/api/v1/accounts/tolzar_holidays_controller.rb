# Tolzar holiday calendar (round 4, c103; Tolzar::Holidays):
#   GET  tolzar/holidays  {holidays}             anyone in the workspace
#   POST tolzar/holidays  {holidays: [{date, name}]}  administrators; replaces the list
# TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarHolidaysController < Api::V1::Accounts::BaseController
  before_action { head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id) }

  def show
    render json: { ok: true, holidays: Tolzar::Holidays.list(Current.account) }
  end

  def save
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    rows = params[:holidays].is_a?(Array) ? params[:holidays].map { |h| h.respond_to?(:permit) ? h.permit(:date, :name) : h } : []
    render json: { ok: true, holidays: Tolzar::Holidays.save!(Current.account, rows) }
  end
end
