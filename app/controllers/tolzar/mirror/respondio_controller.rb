# Tolzar shadow mirror: PUBLIC receiver for respond.io webhooks (Aquarius + Xplorer).
#
# respond.io requires a 200 within 5s (and deactivates the endpoint after >30 errors
# /30 min), so this does the minimum synchronously — verify the HMAC signature over
# the raw body, store the raw event (idempotent on event_id), enqueue the projector,
# return 200. No reply is ever sent back to respond.io from anywhere in the mirror.
class Tolzar::Mirror::RespondioController < ActionController::API
  def create
    tenant = params[:tenant].to_s
    return head(:not_found) unless Tolzar::MirrorConfig.tenant?(tenant)

    raw = request.raw_post
    unless Tolzar::MirrorConfig.valid_signature?(tenant, raw, request.headers['X-Webhook-Signature'].to_s)
      Rails.logger.warn("[tolzar-mirror] bad signature tenant=#{tenant} ip=#{request.remote_ip}")
      return head(:unauthorized)
    end

    body =
      begin
        JSON.parse(raw)
      rescue JSON::ParserError
        return head(:bad_request)
      end

    event = Tolzar::MirrorEvent.create_or_find_by!(event_id: (body['event_id'].presence || SecureRandom.uuid)) do |e|
      e.tenant         = tenant
      e.event_type     = body['event_type']
      e.rio_contact_id = body.dig('contact', 'id')
      e.rio_message_id = body.dig('message', 'messageId')
      e.payload        = body
      e.received_at    = Time.current
    end

    Tolzar::Mirror::ProjectJob.perform_later(event.id) if event.processed_at.nil?
    head :ok
  rescue StandardError => e
    # Never 500 at respond.io (that counts toward deactivation). Log + 200; the row,
    # if stored, will be retried by a later event or a sweeper.
    Rails.logger.error("[tolzar-mirror] ingest error tenant=#{params[:tenant]}: #{e.class} #{e.message}")
    head :ok
  end

  # Secret-guarded read-only verification/ops endpoint (P1 acceptance + P2 ops).
  # Guard reuses the tenant's webhook signing keys — send one as X-Tolzar-Mirror-Key.
  # Returns counts + recent event TYPES/IDS only; never payloads (those carry PII).
  def status
    tenant = params[:tenant].to_s
    return head(:not_found) unless Tolzar::MirrorConfig.tenant?(tenant)
    return head(:unauthorized) unless authed?(tenant)

    scope = Tolzar::MirrorEvent.where(tenant: tenant)
    errored = scope.where.not(error: nil)
    render json: {
      tenant:     tenant,
      total:      scope.count,
      pending:    scope.where(processed_at: nil).count,
      processed:  scope.where.not(processed_at: nil).count,
      errors:     errored.count,
      last_error: errored.order(received_at: :desc).limit(1).pluck(:event_type, :error).first,
      recent:     scope.order(received_at: :desc).limit(10)
                       .pluck(:event_type, :event_id, :received_at)
                       .map { |t, id, at| { event_type: t, event_id: id, received_at: at } }
    }
  end

  # Secret-guarded: re-run projection for a tenant's events. By default only the
  # errored ones; with ?all=1, every event. Used to project the already-stored
  # events against a new/fixed projector. Clears processed_at + error, re-enqueues.
  def reprocess
    tenant = params[:tenant].to_s
    return head(:not_found) unless Tolzar::MirrorConfig.tenant?(tenant)
    return head(:unauthorized) unless authed?(tenant)

    scope = Tolzar::MirrorEvent.where(tenant: tenant)
    target = params[:all].to_s == '1' ? scope : scope.where.not(error: nil)
    ids = target.pluck(:id)
    target.update_all(processed_at: nil, error: nil)
    ids.each { |id| Tolzar::Mirror::ProjectJob.perform_later(id) }
    render json: { tenant: tenant, requeued: ids.size }
  end

  private

  def authed?(tenant)
    provided = request.headers['X-Tolzar-Mirror-Key'].to_s
    provided.present? && Tolzar::MirrorConfig.signing_keys(tenant).any? do |k|
      ActiveSupport::SecurityUtils.secure_compare(provided, k)
    end
  end
end
