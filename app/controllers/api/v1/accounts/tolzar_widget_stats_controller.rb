# Tolzar own widget per-page analytics for administrators: GET tolzar/widget_stats?inbox_id=&days= (7/30).
class Api::V1::Accounts::TolzarWidgetStatsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin

  def show
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id], channel_type: 'Channel::WebWidget')
    return head(:not_found) unless inbox

    days = params[:days].to_i == 7 ? 7 : 30
    render json: { ok: true, own_widget: Tolzar::OwnWidget.on?(Current.account.id), days: days,
                   pages: Tolzar::WidgetStats.report(inbox.id, days: days).first(50) }
  end

  private

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end
end
