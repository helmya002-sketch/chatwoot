# Tolzar: the website's live demo (launch key `live-demo`; docs/reports/TOLZAR-LIVE-DEMO-PLAN-2026-10-31.md).
#   GET  /tolzar/site/demo/businesses   the fictional demo businesses and their suggested prompts
#   POST /tolzar/site/demo              industry, message (<= 300 chars), session (the browser's random id)
# The site posts a simple CORS request (form-encoded, Accept: application/json: no preflight). Answers come from the
# brain's demo engine (brain demo.py: a brain-only account, no workspace touched). This door only keeps what the
# session needs: the last turns, in Redis for 30 minutes, under a hash of the session id. Limits per IP (hour and
# day) and per session (turns). Off unless the brain's TOLZAR_DEMO is on (its 404 passes through).
class Tolzar::SiteDemoController < ActionController::Base
  skip_forgery_protection
  before_action :set_cors_headers

  PER_IP_HOUR = 20
  PER_IP_DAY = 60
  MAX_TURNS = 6
  MAX_MESSAGE = 300
  SESSION_TTL = 30.minutes
  SESSION_ID = /\A[\w-]{8,64}\z/
  CHECKS = %w[price offer rules language].freeze

  def businesses
    res = Tolzar::BrainClient.get('/demo/businesses')
    return render(json: { error: 'off' }, status: :not_found) unless res['status'] == 200

    render json: { businesses: Array(res['businesses']) }
  end

  def create
    return error(:bad_request, 'invalid') unless valid_request?

    wait = ip_wait
    return render(json: { error: 'rate', retry_after: wait }, status: :too_many_requests) if wait

    history = transcript
    return render(json: { error: 'rate', retry_after: SESSION_TTL.to_i }, status: :too_many_requests) if turns(history) >= MAX_TURNS

    messages = history + [{ 'role' => 'visitor', 'text' => message }]
    answer(Tolzar::BrainClient.post('/demo/answer', { industry: params[:industry].to_s, messages: messages }), messages)
  end

  def preflight
    head(allowed_origin ? :no_content : :forbidden)
  end

  private

  def message
    @message ||= params[:message].to_s.strip
  end

  def valid_request?
    message.present? && message.length <= MAX_MESSAGE && params[:industry].to_s.match?(/\A[a-z-]{2,40}\z/) &&
      params[:session].to_s.match?(SESSION_ID)
  end

  def answer(res, messages)
    case res['status']
    when 200
      store(messages + [{ 'role' => 'ai', 'text' => res['reply'].to_s }])
      render json: view(res)
    when 404 then error(:not_found, 'industry_unavailable')
    when 400 then error(:bad_request, 'invalid')
    else error(:service_unavailable, 'busy')
    end
  end

  def view(res)
    checks = (res['checks'] || {}).slice(*CHECKS).transform_values { |v| %w[pass blocked na].include?(v) ? v : 'na' }
    { reply: res['reply'].to_s, checks: checks, handoff: res['handoff'] == true, handoff_reason: res['handoff_reason'],
      why: Array(res['why']).first(4).map(&:to_s), lang: res['lang'].to_s, business: res['business'] || {},
      turns_left: [MAX_TURNS - turns(transcript), 0].max }
  end

  def turns(history)
    history.count { |m| m['role'] == 'visitor' }
  end

  def session_key
    "tolzar:site_demo:#{Digest::SHA256.hexdigest(params[:session].to_s)}"
  end

  def transcript
    parsed = JSON.parse(Redis::Alfred.get(session_key) || '[]')
    parsed.is_a?(Array) ? parsed.last(MAX_TURNS * 2) : []
  rescue JSON::ParserError
    []
  end

  def store(history)
    Redis::Alfred.set(session_key, history.last(MAX_TURNS * 2).to_json, ex: SESSION_TTL.to_i)
  end

  # Seconds to wait when this IP is over its hourly or daily limit, else nil.
  def ip_wait
    ip = request.remote_ip
    hour = count("tolzar:site_demo:ip:#{ip}:h", 1.hour)
    day = count("tolzar:site_demo:ip:#{ip}:d", 1.day)
    return 1.hour.to_i if hour > PER_IP_HOUR
    return 1.day.to_i if day > PER_IP_DAY

    nil
  end

  def count(key, window)
    value = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, window.to_i) if value == 1
    value
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
