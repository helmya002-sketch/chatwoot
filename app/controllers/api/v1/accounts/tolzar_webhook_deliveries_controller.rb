# Tolzar webhook delivery log (round 4, H2): GET tolzar/webhooks/:webhook_id/deliveries, the last 50 deliveries of one
# of this workspace's webhooks (time, event, HTTP status, duration; never the payload, URL or secret).
# Administrators; TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarWebhookDeliveriesController < Api::V1::Accounts::BaseController
  def index
    return head(:not_found) unless Tolzar::WebhookDelivery.on?(Current.account.id)
    return render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?

    webhook = Current.account.webhooks.find_by(id: params[:webhook_id])
    return head(:not_found) unless webhook

    rows = Tolzar::WebhookDelivery.where(webhook_id: webhook.id).order(id: :desc).limit(Tolzar::WebhookDelivery::KEEP)
    render json: { ok: true, deliveries: rows.map(&:view) }
  end
end
