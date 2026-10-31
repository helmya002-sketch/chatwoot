class WebhookJob < ApplicationJob
  queue_as :medium
  #  There are 3 types of webhooks, account, inbox and agent_bot
  # Tolzar (H2): webhook_id comes only for a workspace webhook while its delivery log is on (Tolzar::WebhookDelivery).
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil, webhook_id: nil)
    Webhooks::Trigger.execute(url, payload, webhook_type, secret: secret, delivery_id: delivery_id, webhook_id: webhook_id)
  end
end
