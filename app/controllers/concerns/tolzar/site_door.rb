# Tolzar: what the website's AI doors share (Tolzar::SiteDemoController, Tolzar::SiteConciergeController).
# Simple CORS for TOLZAR_CONTACT_ORIGINS, per-IP limits (hour and day), and the session's last turns in Redis for
# 30 minutes under a hash of the browser's random session id. Each door names its own Redis prefix (door_prefix).
module Tolzar::SiteDoor
  extend ActiveSupport::Concern

  PER_IP_HOUR = 20
  PER_IP_DAY = 60
  SESSION_TTL = 30.minutes
  SESSION_ID = /\A[\w-]{8,64}\z/

  included do
    skip_forgery_protection
    before_action :set_cors_headers
  end

  def preflight
    head(allowed_origin ? :no_content : :forbidden)
  end

  private

  def valid_session?
    params[:session].to_s.match?(SESSION_ID)
  end

  def turns(history)
    history.count { |m| m['role'] == 'visitor' }
  end

  def session_key(suffix = nil)
    ["#{door_prefix}:#{Digest::SHA256.hexdigest(params[:session].to_s)}", suffix].compact.join(':')
  end

  def transcript
    parsed = JSON.parse(Redis::Alfred.get(session_key) || '[]')
    parsed.is_a?(Array) ? parsed.last(max_turns * 2) : []
  rescue JSON::ParserError
    []
  end

  def store(history)
    Redis::Alfred.set(session_key, history.last(max_turns * 2).to_json, ex: SESSION_TTL.to_i)
  end

  # Seconds to wait when this IP is over its hourly or daily limit, else nil.
  def ip_wait
    ip = request.remote_ip
    hour = count("#{door_prefix}:ip:#{ip}:h", 1.hour)
    day = count("#{door_prefix}:ip:#{ip}:d", 1.day)
    return 1.hour.to_i if hour > PER_IP_HOUR
    return 1.day.to_i if day > PER_IP_DAY

    nil
  end

  def count(key, window)
    value = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, window.to_i) if value == 1
    value
  end

  def rate(wait)
    render json: { error: 'rate', retry_after: wait }, status: :too_many_requests
  end

  def error(status, code)
    render json: { error: code }, status: status
  end

  def allowed_origins
    ENV.fetch('TOLZAR_CONTACT_ORIGINS', '').split(',').map(&:strip).compact_blank
  end

  def allowed_origin
    origin = request.headers['Origin'].to_s
    origin if origin.present? && allowed_origins.include?(origin)
  end

  def set_cors_headers
    return unless allowed_origin

    response.headers['Access-Control-Allow-Origin'] = allowed_origin
    response.headers['Vary'] = 'Origin'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Max-Age'] = '600'
  end
end
