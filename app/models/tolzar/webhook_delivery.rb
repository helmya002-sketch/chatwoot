# Tolzar webhook delivery log (round 4, H2), for TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces: one row per delivery of a
# workspace webhook (Settings → Integrations → Webhooks), the last KEEP per webhook, written by Webhooks::Trigger.
# Time, event, HTTP status, duration and a short error kind only; never the payload, the URL, headers or the secret.
# Recording never breaks a delivery. Rows go with their webhook (foreign key, on delete cascade).
class Tolzar::WebhookDelivery < ApplicationRecord
  self.table_name = 'tolzar_webhook_deliveries'
  KEEP = 50

  belongs_to :webhook, class_name: '::Webhook'

  def self.on?(account_id)
    Tolzar::CannedStarters.enabled?(account_id)
  end

  # outcome: { ok:, status:, error: } from Webhooks::Trigger.
  def self.record(webhook_id, event, outcome, duration_ms)
    webhook = ::Webhook.find_by(id: webhook_id)
    return unless webhook && on?(webhook.account_id)

    create!(account_id: webhook.account_id, webhook_id: webhook.id, event: event.to_s.first(64), status: outcome[:status],
            ok: outcome[:ok] == true, error: outcome[:error].to_s.first(32).presence, duration_ms: duration_ms)
    prune(webhook.id)
  rescue StandardError => e
    Rails.logger.warn("[Tolzar] webhook delivery log webhook=#{webhook_id} not recorded: #{e.class}")
  end

  def self.prune(webhook_id)
    keep_from = where(webhook_id: webhook_id).order(id: :desc).offset(KEEP - 1).limit(1).pick(:id)
    where(webhook_id: webhook_id).where('id < :id', id: keep_from).delete_all if keep_from
  end

  def view
    { at: created_at.iso8601, event: event, status: status, ok: ok, error: error, duration_ms: duration_ms }
  end
end
