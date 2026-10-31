# Tolzar lead intake door (Tolzar::LeadIntake): POST /tolzar/leads/:inbox_id/:token with JSON or form fields.
# 404 for a wrong token, an inbox that is not an API inbox, or a workspace not in TOLZAR_LEAD_INTAKE (never says
# which). 600 leads an hour per inbox. A lead_id seen before answers 200 with duplicate: true.
class Tolzar::LeadsController < ActionController::API
  PER_HOUR = 600

  def create
    inbox = Tolzar::LeadIntake.inbox_for(params[:inbox_id], params[:token])
    return head(:not_found) unless inbox
    return render(json: { ok: false, error: 'rate' }, status: :too_many_requests) if over_limit?(inbox)

    out = Tolzar::LeadIntake.new(inbox: inbox, params: lead_params).perform
    render json: { ok: true, **out }, status: (out[:duplicate] ? :ok : :created)
  rescue Tolzar::LeadIntake::Refused => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def lead_params
    params.except(:controller, :action, :inbox_id, :token, :lead).permit!.to_h
  end

  def over_limit?(inbox)
    key = "tolzar:leads:#{inbox.id}:#{Time.current.strftime('%Y%m%d%H')}"
    value = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 2.hours.to_i) if value == 1
    value > PER_HOUR
  end
end
