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

  # Real Workflows (B1): the brain stores, validates and runs them (shadow only).
  def workflows
    render json: get_from_brain("/workflows?account_id=#{account_scope_id}")
  end

  def workflow_save
    render json: post_to_brain('/workflows', { account_id: account_scope_id, workflow: unsafe(params[:workflow]) })
  end

  def workflow_delete
    render json: post_to_brain('/workflows/delete', { account_id: account_scope_id, id: params[:id].to_s })
  end

  def workflow_runs
    query = { account_id: account_scope_id, workflow_id: params[:workflow_id].presence,
              limit: (params[:limit].presence || 100).to_i.clamp(1, 500) }.compact.to_query
    render json: get_from_brain("/workflows/runs?#{query}")
  end

  def workflow_test
    body = { account_id: account_scope_id, id: params[:id].to_s, workflow: unsafe(params[:workflow]),
             contact_id: params[:contact_id].presence&.to_i, conversation_id: params[:conversation_id].presence&.to_i,
             replied: params[:replied] == true || params[:replied].to_s == 'true' }
    render json: post_to_brain('/workflows/test', body.compact)
  end

  def workflow_templates
    query = { won_field: params[:won_field].presence, won_value: params[:won_value].presence }.compact.to_query
    render json: get_from_brain("/workflows/templates?#{query}")
  end

  # Connect Facebook & Instagram (per workspace; the brain keeps the tokens encrypted).
  def meta_status
    render json: get_from_brain("/meta/status?account_id=#{account_scope_id}")
  end

  def meta_connect_url
    render json: post_to_brain('/meta/connect_url', { account_id: account_scope_id })
  end

  def meta_select
    render json: post_to_brain('/meta/select', { account_id: account_scope_id, pages: Array(params[:pages]).map { |p| unsafe(p) },
                                                 comments: params.key?(:comments) ? unsafe(params[:comments]) : nil }.compact)
  end

  def meta_disconnect
    render json: post_to_brain('/meta/disconnect', { account_id: account_scope_id })
  end

  # Batch 2-3 brain features, admin-only, shadow only. GET reads pass through; POST settings
  # carry the account id and the signed-in user (audited in the brain).
  BRAIN_GETS = { 'usage' => '/usage', 'sla' => '/sla', 'media' => '/media', 'dedupe' => '/dedupe',
                 'channels' => '/channels', 'attribution' => '/attribution', 'broadcasts' => '/broadcasts' }.freeze
  BRAIN_POSTS = { 'sla' => '/sla', 'media' => '/media', 'dedupe_refresh' => '/dedupe/refresh', 'channels' => '/channels',
                  'links' => '/links', 'broadcasts' => '/broadcasts', 'broadcasts_preview' => '/broadcasts/preview',
                  'broadcasts_run' => '/broadcasts/run', 'mcp_token' => '/mcp-token' }.freeze

  def brain_get
    path = BRAIN_GETS[params[:feature].to_s]
    return head(:not_found) if path.nil?

    extra = params[:days].present? ? "&days=#{params[:days].to_i}" : ''
    render json: get_from_brain("#{path}?account_id=#{account_scope_id}#{extra}")
  end

  def brain_post
    path = BRAIN_POSTS[params[:feature].to_s]
    return head(:not_found) if path.nil?

    body = unsafe(params.except(:controller, :action, :account_id, :feature, :tolzar)).to_h
    render json: post_to_brain(path, body.merge('account_id' => account_scope_id))
  end

  # Export workspace (A5): a background job writes a .tar.gz, downloadable for 7 days.
  def export_start
    Tolzar::WorkspaceExportJob.perform_later(account_scope_id)
    post_to_brain('/audit/record', { account_id: account_scope_id, action: 'workspace.export_requested', target: 'chatwoot' })
    render json: { ok: true, queued: true }
  end

  def export_status
    blobs = Tolzar::WorkspaceExportJob.blobs(account_scope_id).where('created_at >= ?', Tolzar::WorkspaceExportJob::KEEP.ago).limit(5)
    render json: { ok: true, exports: blobs.map { |b| { id: b.id, filename: b.filename.to_s, size: b.byte_size, created_at: b.created_at } } }
  end

  def export_download
    blob = Tolzar::WorkspaceExportJob.blobs(account_scope_id).where('created_at >= ?', Tolzar::WorkspaceExportJob::KEEP.ago)
                                     .find_by(id: params[:id])
    return head(:not_found) if blob.nil?

    send_data blob.download, filename: blob.filename.to_s, type: 'application/gzip'
  end

  # Audit log (A6): Chatwoot's own audits for this workspace plus the brain's settings log.
  AUDIT_HIDDEN = /token|secret|password|otp/i

  def audit
    limit = (params[:limit].presence || 200).to_i.clamp(1, 1000)
    rows = Audited::Audit.where(associated_type: 'Account', associated_id: account_scope_id)
                         .or(Audited::Audit.where(auditable_type: 'Account', auditable_id: account_scope_id))
                         .order(created_at: :desc).limit(limit)
    users = User.where(id: rows.map(&:user_id).compact.uniq).index_by(&:id)
    chatwoot = rows.map do |a|
      changes = (a.audited_changes || {}).reject { |k, _| k.to_s.match?(AUDIT_HIDDEN) }
      { source: 'chatwoot', at: a.created_at, action: "#{a.auditable_type.underscore}.#{a.action}",
        target: "#{a.auditable_type} #{a.auditable_id}",
        actor: users[a.user_id]&.email || a.username || 'system', changes: changes }
    end
    brain = (get_from_brain("/audit?account_id=#{account_scope_id}&limit=#{limit}")['entries'] || []).map do |e|
      { source: 'brain', at: e['at'], action: e['action'], target: e['target'], actor: e['actor'], changes: e['changes'] }
    end
    render json: { ok: true, entries: (chatwoot + brain).sort_by { |e| e[:at].to_s }.reverse.first(limit) }
  end

  # Shadow-eval scoreboard for the Reports page (would-vs-did, go-live checks).
  def scoreboard
    days = (params[:days].presence || 30).to_i.clamp(1, 90)
    render json: get_from_brain("/scoreboard?account_id=#{account_scope_id}&days=#{days}")
  end

  private

  # Who made the change, for the brain's audit log (A6).
  def actor_label
    "#{Current.user&.id}:#{Current.user&.email}"
  end

  def unsafe(value)
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
  end

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
    req['X-Tolzar-Actor'] = actor_label
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
    req['X-Tolzar-Actor'] = actor_label
    JSON.parse(http.request(req).body)
  rescue StandardError => e
    Rails.logger.warn("tolzar agents brain error: #{e.class} #{e.message}")
    { ok: false, error: 'brain_unreachable', agents: [], default_id: nil }
  end
end
