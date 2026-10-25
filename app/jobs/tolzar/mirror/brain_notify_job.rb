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
# handles it unchanged.
class Tolzar::Mirror::BrainNotifyJob < ApplicationJob
  queue_as :medium

  def perform(message_id)
    url = ENV['TOLZAR_BRAIN_HOOK_URL'].to_s
    return if url.blank?

    message = Message.find_by(id: message_id)
    return if message.nil?
    return unless message.incoming? # only a customer turn arms the brain
    return unless Tolzar::MirrorConfig.mirror_inbox?(message.inbox)

    payload = message.webhook_data.merge(event: 'message_created')
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 3
    http.read_timeout = 8
    req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    req.body = payload.to_json
    res = http.request(req)
    return if res.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("[tolzar-mirror] brain notify non-2xx message=#{message_id} status=#{res.code}")
  rescue StandardError => e
    # A brain outage must never break projection; swallow and log.
    Rails.logger.warn("[tolzar-mirror] brain notify failed message=#{message_id} #{e.class}: #{e.message}")
  end
end
