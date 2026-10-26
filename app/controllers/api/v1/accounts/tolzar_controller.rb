# Tolzar: admin-only proxy to the internal "brain" service (aquarius-inbox) so the
# AI-Agents in-app test chat can get a real reply from the self-hosted model (Qwen).
# The brain is internal-network only (no published port); this proxy is the single,
# authenticated door to it. Nothing here touches a live conversation.
class Api::V1::Accounts::TolzarController < Api::V1::Accounts::BaseController
  before_action :ensure_admin

  def agent_test
    body = {
      message: params[:message].to_s,
      instructions: params[:instructions].to_s,
      account_id: account_scope_id,
      history: Array(params[:history]).first(20).map { |m| { role: m[:role].to_s, content: m[:content].to_s } }
    }
    render json: post_to_brain('/agent-test', body)
  end

  # Server-side AI-Agent configs (stored by the brain; the brain reads + uses them).
  def agents
    render json: get_from_brain("/agents?account_id=#{account_scope_id}")
  end

  def agent_save
    agent = params[:agent].respond_to?(:to_unsafe_h) ? params[:agent].to_unsafe_h : params[:agent]
    render json: post_to_brain('/agents', { account_id: account_scope_id, agent: agent })
  end

  def agent_delete
    render json: post_to_brain('/agents/delete', { account_id: account_scope_id, id: params[:id].to_s })
  end

  def agent_default
    render json: post_to_brain('/agents/default', { account_id: account_scope_id, id: params[:id].to_s })
  end

  private

  def account_scope_id
    Current.account&.id || params[:account_id]
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end

  def post_to_brain(path, body)
    base = ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080')
    uri = URI.join(base, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 130
    http.open_timeout = 5
    req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    # Shared secret so only this proxy can reach the brain's internal endpoints.
    # Harmless until the brain is configured to require it (TOLZAR_BRAIN_SECRET).
    secret = ENV['TOLZAR_BRAIN_SECRET'].to_s
    req['X-Tolzar-Brain-Secret'] = secret unless secret.empty?
    req.body = body.to_json
    res = http.request(req)
    JSON.parse(res.body)
  rescue StandardError => e
    Rails.logger.warn("tolzar agent_test brain error: #{e.class} #{e.message}")
    { ok: false, error: 'brain_unreachable', reply: "The brain is not reachable right now (#{e.class})." }
  end

  def get_from_brain(path)
    base = ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080')
    uri = URI.join(base, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 30
    http.open_timeout = 5
    req = Net::HTTP::Get.new(uri.request_uri)
    secret = ENV['TOLZAR_BRAIN_SECRET'].to_s
    req['X-Tolzar-Brain-Secret'] = secret unless secret.empty?
    JSON.parse(http.request(req).body)
  rescue StandardError => e
    Rails.logger.warn("tolzar agents brain error: #{e.class} #{e.message}")
    { ok: false, error: 'brain_unreachable', agents: [], default_id: nil }
  end
end
