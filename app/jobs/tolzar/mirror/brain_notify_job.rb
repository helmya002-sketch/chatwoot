# Tolzar shadow mirror: hand a freshly-projected customer message to the Tolzar
# brain for read-only evaluation.
#
# This is a plain internal HTTP POST from our OWN code — deliberately NOT a
# Chatwoot account/agent-bot webhook. Chatwoot's webhook sender (Webhooks::Trigger)
# enforces an SSRF guard that refuses private hostnames ("Hostname 'tolzar-brain'
# has no public ip addresses"), so it cannot reach the brain, which lives on the
# private Docker network by design. Our own Net::HTTP call is not subject to that
# guard. The brain evaluates in shadow/eval mode and writes a private "Tolzar
# would…" note back into the mirror conversation; it never sends a public reply.
#
# The payload is byte-identical to what a Chatwoot account webhook would have sent
# (message.webhook_data + event), so the brain's existing /hooks/chatwoot parser
# handles it unchanged. It is signed like Chatwoot signs an agent-bot delivery (Webhooks::Trigger:
# X-Chatwoot-Timestamp + X-Chatwoot-Signature = "sha256=" + hex HMAC-SHA256(secret, "<ts>.<body>")),
# with BRAIN_WEBHOOK_SECRET, and only when the URL's host is the brain's (never to another host).
# Every request also carries X-Chatwoot-Delivery: <uuid>, like Chatwoot's own deliveries; the brain
# accepts each delivery id once, so a captured signed delivery cannot be replayed inside the 300 s
# window. The id is the job's ActiveJob job_id (a UUID, kept across retries of the same job), so a
# retry of a delivery the brain already accepted is refused instead of evaluated twice.
#
# Retries (HIGH 2, full-rel review 2026-10-29): a brain that is restarting or overloaded must not lose the
# delivery. A connection error (refused, reset, timed out) and a 408/429/5xx answer raise RetryableDelivery,
# retried by ActiveJob up to ATTEMPTS times with exponential backoff (10 s, 20 s, 40 s ... capped at 5 min),
# with the same delivery id. 2xx is done; so is 401 "replayed delivery" (the brain already accepted this id
# on an earlier attempt whose answer we lost). Any other 4xx is a permanent failure: logged, not retried.
# Projection never waits on any of this (the job runs after it).
class Tolzar::Mirror::BrainNotifyJob < ApplicationJob
  class RetryableDelivery < StandardError; end

  ATTEMPTS = 8
  BACKOFF = ->(executions) { [10 * (2**(executions - 1)), 300].min }
  CONNECTION_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError, OpenSSL::SSL::SSLError, EOFError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
    Errno::EPIPE, Errno::ETIMEDOUT
  ].freeze

  queue_as :medium

  retry_on RetryableDelivery, wait: BACKOFF, attempts: ATTEMPTS do |job, error|
    Rails.logger.warn("[tolzar-mirror] brain notify gave up message=#{job.arguments.first} after #{ATTEMPTS} attempts " \
                      "delivery=#{job.job_id}: #{error.message}") # RetryableDelivery's own message: class / status only
  end

  def perform(message_id)
    url = ENV['TOLZAR_BRAIN_HOOK_URL'].to_s
    return if url.blank?

    message = Message.find_by(id: message_id)
    return if message.nil?
    return unless message.incoming? # only a customer turn arms the brain
    return unless Tolzar::MirrorConfig.mirror_inbox?(message.inbox)
    return if Tolzar::Subscription.ai_paused?(message.account_id)

    handle_response(post(url, message.webhook_data.merge(event: 'message_created'), message.account_id), message_id)
  rescue RetryableDelivery
    raise
  rescue StandardError => e
    # Anything unexpected (not a brain outage) is logged once, never retried.
    Rails.logger.warn("[tolzar-mirror] brain notify failed message=#{message_id} #{Tolzar::Mirror::LogSafe.describe(e)}")
  end

  private

  def post(url, payload, account_id)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 3
    http.read_timeout = 8
    req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    req.body = payload.to_json
    req['X-Chatwoot-Delivery'] = delivery_id
    sign_for_brain(req, uri, account_id) # a fresh timestamp + signature on every attempt, the same delivery id
    http.request(req)
  rescue *CONNECTION_ERRORS => e
    raise RetryableDelivery, Tolzar::Mirror::LogSafe.describe(e)
  end

  def handle_response(res, message_id)
    status = res.code.to_i
    return if res.is_a?(Net::HTTPSuccess) || replayed_delivery?(res)
    raise RetryableDelivery, "status #{status}" if status == 408 || status == 429 || status >= 500

    Rails.logger.warn("[tolzar-mirror] brain notify refused message=#{message_id} status=#{status} (not retried)")
  end

  # The brain answers 401 {"detail":"replayed delivery"} to an id it already accepted.
  def replayed_delivery?(res)
    res.code.to_i == 401 && res.body.to_s.include?('replayed delivery')
  end

  def delivery_id
    @delivery_id ||= job_id.presence || SecureRandom.uuid
  end

  def sign_for_brain(req, uri, account_id)
    master = ENV['BRAIN_WEBHOOK_SECRET'].to_s
    return if master.empty? || uri.host != Tolzar::BrainClient.brain_host

    key = self.class.hook_key(master, account_id)
    ts = Time.now.to_i.to_s
    req['X-Chatwoot-Timestamp'] = ts
    req['X-Chatwoot-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{ts}.#{req.body}")}"
  end

  # H2 (full-sec): per-account hook keys. TOLZAR_HOOK_KEY_MODE=derived signs with
  #   HKDF-SHA256(ikm = BRAIN_WEBHOOK_SECRET, salt = "", info = "tolzar-hook-v1:<account_id>", length 32)
  # (the raw 32 bytes are the HMAC key), so a leaked key forges one account's deliveries only.
  # Any other value (default "master", until the brain verifies derived keys) signs with the master.
  def self.hook_key(master, account_id)
    return master unless ENV.fetch('TOLZAR_HOOK_KEY_MODE', 'master').to_s.strip.downcase == 'derived'

    derive_hook_key(master, account_id)
  end

  def self.derive_hook_key(master, account_id)
    OpenSSL::KDF.hkdf(master.to_s, salt: '', info: "tolzar-hook-v1:#{account_id.to_i}", length: 32, hash: 'SHA256')
  end
end
