# Tolzar booking-system webhook door (Tolzar::BookingHook): POST /tolzar/booking_hooks/:connector_id, JSON, signed.
# 404 for an unknown connector or a workspace without TOLZAR_BOOKING_CONNECTOR; 401 for a bad or stale signature.
class Tolzar::BookingHooksController < ActionController::API
  MAX_BODY = 64.kilobytes

  def create
    connector = Tolzar::BookingConnector.find_by(id: params[:connector_id])
    return head(:not_found) unless connector && Tolzar::BookingConnector.enabled?(connector.account_id)

    body = request.raw_post.to_s
    return head(:payload_too_large) if body.bytesize > MAX_BODY

    Tolzar::BookingHook.verify!(connector, timestamp: request.headers['X-Tolzar-Timestamp'],
                                           signature: request.headers['X-Tolzar-Signature'], body: body)
    payload = JSON.parse(body)
    return head(:bad_request) unless payload.is_a?(Hash)

    render json: { ok: true, result: Tolzar::BookingHook.new(connector, payload).perform }
  rescue Tolzar::BookingHook::Refused => e
    status = %w[stale signature].include?(e.message) ? :unauthorized : :unprocessable_entity
    render json: { ok: false, error: e.message }, status: status
  rescue JSON::ParserError
    head :bad_request
  end
end
