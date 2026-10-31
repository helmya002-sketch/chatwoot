# Tolzar own widget: one per-page counter tick (Tolzar::WidgetStats) — POST /api/v1/widget/tolzar_stats
# {kind: open|start, page} with the visitor's widget token. Only for TOLZAR_OWN_WIDGET_ACCOUNTS workspaces; at most
# 30 ticks a minute per visitor.
class Api::V1::Widget::TolzarStatsController < Api::V1::Widget::BaseController
  PER_MINUTE = 30

  def create
    return head(:not_found) unless Tolzar::OwnWidget.on?(@web_widget.account_id)
    return head(:too_many_requests) if over_limit?

    Tolzar::WidgetStats.record(@web_widget.inbox.id, params[:kind].to_s, params[:page].to_s)
    head :no_content
  end

  private

  def over_limit?
    k = "tolzar:widget_stats:rate:#{@contact_inbox&.id}:#{Time.current.strftime('%Y%m%d%H%M')}"
    n = Redis::Alfred.incr(k)
    Redis::Alfred.expire(k, 120) if n == 1
    n > PER_MINUTE
  end
end
