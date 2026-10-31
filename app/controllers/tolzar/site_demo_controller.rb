# Tolzar: the website's live demo (launch key `live-demo`; docs/reports/TOLZAR-LIVE-DEMO-PLAN-2026-10-31.md).
#   GET  /tolzar/site/demo/businesses   the fictional demo businesses and their suggested prompts
#   POST /tolzar/site/demo              industry, message (<= 300 chars), session (the browser's random id)
# The site posts a simple CORS request (form-encoded, Accept: application/json: no preflight). Answers come from the
# brain's demo engine (brain demo.py: a brain-only account, no workspace touched). This door only keeps what the
# session needs: the last turns, in Redis for 30 minutes, under a hash of the session id. Limits per IP (hour and
# day) and per session (turns) come from Tolzar::SiteDoor. Off unless the brain's TOLZAR_DEMO is on (its 404 passes
# through).
class Tolzar::SiteDemoController < ActionController::Base
  include Tolzar::SiteDoor

  MAX_TURNS = 6
  MAX_MESSAGE = 300
  CHECKS = %w[price offer rules language].freeze

  def businesses
    res = Tolzar::BrainClient.get('/demo/businesses')
    return render(json: { error: 'off' }, status: :not_found) unless res['status'] == 200

    render json: { businesses: Array(res['businesses']) }
  end

  def create
    return error(:bad_request, 'invalid') unless valid_request?

    wait = ip_wait
    return rate(wait) if wait

    history = transcript
    return rate(SESSION_TTL.to_i) if turns(history) >= MAX_TURNS

    messages = history + [{ 'role' => 'visitor', 'text' => message }]
    answer(Tolzar::BrainClient.post('/demo/answer', { industry: params[:industry].to_s, messages: messages }), messages)
  end

  private

  def door_prefix
    'tolzar:site_demo'
  end

  def max_turns
    MAX_TURNS
  end

  def message
    @message ||= params[:message].to_s.strip
  end

  def valid_request?
    message.present? && message.length <= MAX_MESSAGE && params[:industry].to_s.match?(/\A[a-z-]{2,40}\z/) &&
      valid_session?
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
end
