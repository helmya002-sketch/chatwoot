class AgentBots::WebhookJob < WebhookJob
  queue_as :high

  RETRIES_EXHAUSTED = proc do |job, error|
    url, payload, webhook_type = job.arguments
    kwargs = job.arguments.last.is_a?(Hash) ? job.arguments.last : {}
    Webhooks::Trigger.new(url, payload, webhook_type || :agent_bot_webhook, secret: kwargs[:secret],
                                                                            delivery_id: kwargs[:delivery_id]).handle_failure(error)
  end

  # Tolzar: deliveries to the Tolzar brain (also retried on 502/503/504 and when the brain cannot be reached,
  # see Webhooks::Trigger::RETRYABLE_TOLZAR_BRAIN_STATUSES) get 8 attempts with exponential backoff
  # (10 s, 20 s, 40 s ... capped at 5 min), long enough to ride out a brain restart or redeploy.
  TOLZAR_BRAIN_ATTEMPTS = 8
  TOLZAR_BRAIN_BACKOFF = ->(executions) { [10 * (2**(executions - 1)), 300].min }

  retry_on Webhooks::Trigger::RetryableError, wait: 3.seconds, attempts: 3, &RETRIES_EXHAUSTED
  # Declared after the generic handler so it wins for this subclass (ActiveJob checks the last one first).
  retry_on Webhooks::Trigger::TolzarBrainRetryableError, wait: TOLZAR_BRAIN_BACKOFF, attempts: TOLZAR_BRAIN_ATTEMPTS, &RETRIES_EXHAUSTED

  def perform(url, payload, webhook_type = :agent_bot_webhook, secret: nil, delivery_id: nil)
    super(url, payload, webhook_type, secret: secret, delivery_id: delivery_id)
  rescue Webhooks::Trigger::RetryableError => e
    Rails.logger.warn("[AgentBots::WebhookJob] attempt #{executions} failed #{e.class.name} payload=#{payload.to_json}")
    raise
  end
end
