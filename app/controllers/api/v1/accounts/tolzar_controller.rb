# Tolzar: admin-only proxy to the internal "brain" service (aquarius-inbox) so the
# AI-Agents in-app test chat can get a real reply from the self-hosted model (Qwen).
# The brain is internal-network only (no published port); this proxy is the single,
# authenticated door to it. Nothing here touches a live conversation.
class Api::V1::Accounts::TolzarController < Api::V1::Accounts::BaseController
  before_action :ensure_admin, except: %i[branding_view pack_view]
  # Owner-only (H3): every write that changes the workspace's settings or data. Tests, previews and
  # reads stay open to every administrator.
  before_action :ensure_owner, only: %i[export_start export_download meta_connect_url meta_disconnect meta_select
                                        agent_save agent_delete agent_default workflow_save workflow_delete
                                        workspace_settings_save price_source_save price_source_test go_live kill_switch
                                        kill_switch_release]

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

  # Login-CSRF binding: the link only completes in THIS browser. A random 32-byte value goes into
  # an HttpOnly cookie scoped to the public callback (/tolzar/meta; SameSite=Lax so it survives
  # Meta's top-level GET redirect back); the brain keeps only its sha256 with the state.
  META_BIND_COOKIE = :tolzar_meta_bind
  META_BIND_TTL = 15.minutes

  def meta_connect_url
    bind = SecureRandom.urlsafe_base64(32)
    cookies[META_BIND_COOKIE] = { value: bind, httponly: true, secure: true, same_site: :lax,
                                  path: '/tolzar/meta', max_age: META_BIND_TTL.to_i, expires: META_BIND_TTL.from_now }
    render json: post_to_brain('/meta/connect_url', { account_id: account_scope_id,
                                                      bind_hash: Digest::SHA256.hexdigest(bind) })
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
                 'channels' => '/channels', 'attribution' => '/attribution', 'broadcasts' => '/broadcasts',
                 'learned' => '/learned', 'explain' => '/explain', 'recovery' => '/recovery',
                 'qa' => '/qa', 'brief' => '/brief', 'memory' => '/memory', 'scores' => '/scores',
                 'agent_templates' => '/agents/templates', 'roles' => '/roles', 'branding' => '/branding',
                 # Round 1: trust & privacy, channels, AI limits, usage, results.
                 'compliance' => '/compliance', 'retention' => '/retention', 'dsar_export' => '/dsar/export',
                 'sms' => '/sms', 'crm_sync' => '/crm-sync', 'crm_sync_runs' => '/crm-sync/runs',
                 'commerce' => '/commerce', 'commerce_templates' => '/commerce/templates',
                 'negotiation' => '/negotiation', 'agent_teams' => '/agent-teams', 'tuning' => '/tuning',
                 'roi' => '/roi', 'quotas' => '/quotas',
                 # Round 2: reading customers' attachments (PDFs), Off / Shadow.
                 'documents' => '/documents',
                 # An AI agent's price-feed key: status only ({set, last4}), never the value.
                 'credentials_prices' => '/credentials/prices' }.freeze
  BRAIN_POSTS = { 'sla' => '/sla', 'media' => '/media', 'dedupe_refresh' => '/dedupe/refresh', 'channels' => '/channels',
                  'links' => '/links', 'broadcasts' => '/broadcasts', 'broadcasts_preview' => '/broadcasts/preview',
                  'broadcasts_run' => '/broadcasts/run', 'mcp_token' => '/mcp-token',
                  'learned_status' => '/learned/status', 'translate' => '/translate', 'recovery' => '/recovery',
                  'qa_rubric' => '/qa/rubric', 'brief_build' => '/brief/build', 'reviews_draft' => '/reviews/draft',
                  'ask' => '/ask', 'roles' => '/roles', 'knowledge_refresh' => '/agents/knowledge/refresh',
                  'branding' => '/branding',
                  'compliance' => '/compliance', 'retention' => '/retention', 'dsar_delete' => '/dsar/delete',
                  'sms' => '/sms', 'sms_preview' => '/sms/preview', 'crm_sync' => '/crm-sync',
                  'crm_sync_preview' => '/crm-sync/preview', 'commerce' => '/commerce',
                  'commerce_catalogue_sync' => '/commerce/catalogue-sync', 'commerce_order_status' => '/commerce/order-status',
                  'negotiation' => '/negotiation', 'agent_teams' => '/agent-teams', 'tuning_run' => '/tuning/run',
                  'tuning_decide' => '/tuning/decide', 'quotas' => '/quotas', 'documents' => '/documents',
                  # Write-only key, stored encrypted by the brain (Owner-only: not in ADMIN_POSTS).
                  'credentials_prices' => '/credentials/prices' }.freeze
  # Roles (E2, H3): every POST that changes settings or data is Owner-only. Only these previews, drafts,
  # reads and recomputed caches stay open to every administrator (a Manager). A new BRAIN_POSTS entry is
  # Owner-only unless it is added here.
  ADMIN_POSTS = %w[broadcasts_preview sms_preview crm_sync_preview commerce_order_status translate ask
                   reviews_draft brief_build dedupe_refresh tuning_run].freeze
  OWNER_POSTS = (BRAIN_POSTS.keys - ADMIN_POSTS).freeze
  OWNER_GETS = %w[dsar_export].freeze
  ROLES = %w[owner manager agent].freeze

  def brain_get
    path = BRAIN_GETS[params[:feature].to_s]
    return head(:not_found) if path.nil?
    return render(json: { ok: false, error: 'owner_only' }, status: :forbidden) if OWNER_GETS.include?(params[:feature].to_s) && !owner?

    extra = +''
    extra << "&days=#{params[:days].to_i}" if params[:days].present?
    extra << "&conversation_id=#{params[:conversation_id].to_i}" if params[:conversation_id].present?
    extra << "&contact_id=#{params[:contact_id].to_i}" if params[:contact_id].present?
    extra << "&agent_id=#{CGI.escape(params[:agent_id].to_s.first(80))}" if params[:agent_id].present?
    res = get_from_brain("#{path}?account_id=#{account_scope_id}#{extra}")
    # The account owner (H3) is always an Owner; the Roles page shows it as fixed.
    res = res.merge('owner_user_id' => Tolzar::AccountOwner.user_id(Current.account)) if params[:feature].to_s == 'roles'
    render json: res
  end

  def brain_post
    path = BRAIN_POSTS[params[:feature].to_s]
    return head(:not_found) if path.nil?
    return render(json: { ok: false, error: 'owner_only' }, status: :forbidden) if OWNER_POSTS.include?(params[:feature].to_s) && !owner?

    # Rails route params (controller, action, the .json `format`) are not part of the brain request.
    body = unsafe(params.except(:controller, :action, :format, :account_id, :feature, :tolzar)).to_h
    if params[:feature].to_s == 'roles'
      refused = role_change_refusal(body)
      return render(json: { ok: false, error: refused[0] }, status: refused[1]) if refused
    end
    body = body.merge('account_id' => account_scope_id)
    # The brain refuses to demote the account owner / the last Owner too; it learns the owner
    # from the server side only (never from the browser).
    body = body.merge('owner_user_id' => Tolzar::AccountOwner.user_id(Current.account)) if params[:feature].to_s == 'roles'
    render json: post_to_brain(path, body)
  end

  # White-label (R11): every member of the workspace reads its branding (name, colour, logo,
  # support e-mail; nothing else) so the app looks like the agency's product for them too.
  def branding_view
    b = get_from_brain("/branding?account_id=#{account_scope_id}")['branding'] || {}
    render json: { ok: true, branding: b.slice('product_name', 'color', 'logo_url', 'support_email') }
  end

  # The workspace's industry pack (generic SaaS): which extra contact attributes the contact pane
  # shows, under which label. Read-only labels, nothing secret: every member reads it.
  def pack_view
    res = get_from_brain("/workspace/pack?account_id=#{account_scope_id}")
    fields = Array(res['fields']).map { |f| f.slice('key', 'kind', 'label') }
    render json: { ok: true, pack: res['pack'], fields: fields }
  end

  # Export workspace (A5): a background job writes a .tar.gz, downloadable for 7 days. Only the
  # blobs the job recorded for this account are listed or served (H4), never a lookup by filename.
  def export_start
    Tolzar::WorkspaceExportJob.perform_later(account_scope_id)
    post_to_brain('/audit/record', { account_id: account_scope_id, action: 'workspace.export_requested', target: 'chatwoot' })
    render json: { ok: true, queued: true }
  end

  def export_status
    tokens = Tolzar::WorkspaceExportJob.tokens(account_scope_id)
    blobs = Tolzar::WorkspaceExportJob.blobs(account_scope_id).where('created_at >= ?', Tolzar::WorkspaceExportJob::KEEP.ago).limit(5)
    exports = blobs.map { |b| { token: tokens[b.id], filename: b.filename.to_s, size: b.byte_size, created_at: b.created_at } }
    render json: { ok: true, exports: exports }
  end

  # H1 (full-sec): found by its random token + this account, never by the sequential blob id, and
  # never stored by a proxy cache (LSCache keys on cookies and honours these headers).
  def export_download
    blob = Tolzar::WorkspaceExportJob.find_by_token(account_scope_id, params[:token])
    return head(:not_found) unless Tolzar::WorkspaceExportJob.export_blob?(blob, account_scope_id)
    return head(:not_found) if blob.created_at < Tolzar::WorkspaceExportJob::KEEP.ago

    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['X-LiteSpeed-Cache-Control'] = 'no-cache'
    send_data blob.download, filename: blob.filename.to_s, type: 'application/gzip'
  end

  # Audit log (A6): Chatwoot's own audits for this workspace plus the brain's settings log.
  AUDIT_HIDDEN = /token|secret|password|otp|api_key|account_sid|credential/i

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

  # Workspace settings in the brain's DB on top of the yaml defaults (brain workspace_settings.py).
  # Every administrator reads them; only an Owner saves. The reply also says who is looking
  # (viewer_role) and the workspace's own name, so the page can lock the Owner-only controls and
  # know what the go-live confirmation must say. The brain's 400 / 409 / 422 keep their status.
  def workspace_settings
    res = get_from_brain("/workspace/settings?account_id=#{account_scope_id}")
    render_brain(res.merge('viewer_role' => tolzar_role_of(Current.account_user), 'account_name' => Current.account.name))
  end

  def workspace_settings_save
    body = { account_id: account_scope_id, version: Integer(params[:version].to_s, exception: false),
             set: unsafe(params[:set]) || {}, unset: Array(params[:unset]).map(&:to_s) }
    render_brain(post_to_brain('/workspace/settings', body))
  end

  # An AI agent's price source (url | feed | table | commerce). Test fetch is read-only (every
  # administrator); saving is Owner-only.
  AGENT_ID = /\A[A-Za-z0-9_-]{1,80}\z/

  def price_source
    return head(:not_found) unless params[:agent_id].to_s.match?(AGENT_ID)

    render_brain(get_from_brain("#{price_source_path}?account_id=#{account_scope_id}"))
  end

  def price_source_save
    return head(:not_found) unless params[:agent_id].to_s.match?(AGENT_ID)

    render_brain(post_to_brain(price_source_path, price_source_body))
  end

  def price_source_test
    return head(:not_found) unless params[:agent_id].to_s.match?(AGENT_ID)

    render_brain(post_to_brain("#{price_source_path}/test", price_source_body))
  end

  # Going live, per inbox of THIS account (Owner-only). The brain checks the confirmation against
  # the workspace name, so the proxy passes the account's real name from the server side; a value
  # from the browser is never forwarded. The brain refuses (422 not_live_ready) unless every live
  # check is clear.
  def go_live
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id].to_i)
    return render(json: { ok: false, error: 'inbox_not_found' }, status: :not_found) if inbox.nil?

    mode = params[:mode].to_s
    return render(json: { ok: false, error: 'invalid_mode' }, status: :bad_request) unless %w[live shadow].include?(mode)

    render_brain(post_to_brain('/workspace/go-live', { account_id: account_scope_id, inbox_id: inbox.id, mode: mode,
                                                       confirm: params[:confirm].to_s, account_name: Current.account.name }))
  end

  # Every inbox of this workspace back to Shadow, now (Owner-only, no confirmation needed).
  def kill_switch
    render_brain(post_to_brain('/workspace/kill-switch', { account_id: account_scope_id }))
  end

  # The kill switch is a lock (pass 8): go-live is refused until an Owner releases it. Releasing
  # turns nothing live; each inbox needs its own go-live again.
  def kill_switch_release
    render_brain(post_to_brain('/workspace/kill-switch/release', { account_id: account_scope_id }))
  end

  # Shadow-eval scoreboard for the Reports page (would-vs-did, go-live checks).
  def scoreboard
    days = (params[:days].presence || 30).to_i.clamp(1, 90)
    render json: get_from_brain("/scoreboard?account_id=#{account_scope_id}&days=#{days}")
  end

  private

  # A member's Tolzar role (H3), decided here, not by the brain's default: Chatwoot agents are agents;
  # the account owner is always an Owner; any other administrator is a Manager unless the brain's role
  # table explicitly says 'owner' (an Owner promoted them).
  #
  # KNOWN LIMIT (full-sec review 2026-10-29, LOW): a Manager is a Chatwoot `administrator` underneath.
  # Tolzar's owner-only gates (OWNER_POSTS / OWNER_GETS, ensure_owner: export, MCP token, Meta connect,
  # role changes) hold only for the Tolzar endpoints in this controller. Everywhere else in Chatwoot
  # core (inboxes, channel credentials, integrations, webhooks, agents, account settings, Chatwoot's
  # own reports and CSV exports) a Manager has the same administrator rights as an Owner. Closing it
  # needs a Chatwoot custom role or per-controller policy changes; until then, make someone a Manager
  # only if you would make them a Chatwoot administrator.
  def tolzar_role_of(account_user)
    return 'agent' unless account_user&.administrator?
    return 'owner' if account_user.user_id == Tolzar::AccountOwner.user_id(Current.account)

    role_table[account_user.user_id.to_s] == 'owner' ? 'owner' : 'manager'
  end

  def role_table
    @role_table ||= get_from_brain(
      "/roles?account_id=#{account_scope_id}&owner_user_id=#{Tolzar::AccountOwner.user_id(Current.account)}"
    )['roles'] || {}
  end

  def owner?
    tolzar_role_of(Current.account_user) == 'owner'
  end

  # Only an Owner reaches this (OWNER_POSTS). The account owner can't be demoted, and the last
  # Owner can't be demoted either. Returns [error, status] or nil.
  def role_change_refusal(body)
    role = body['role'].to_s
    member = Current.account.account_users.find_by(user_id: body['user_id'].to_i)
    return ['invalid_role', :unprocessable_entity] if member.nil? || ROLES.exclude?(role)
    return if role == 'owner'
    return ['account_owner_fixed', :forbidden] if member.user_id == Tolzar::AccountOwner.user_id(Current.account)

    owners = Current.account.account_users.administrator.select { |au| tolzar_role_of(au) == 'owner' }
    ['last_owner', :forbidden] if owners.map(&:user_id) == [member.user_id]
  end

  def price_source_path
    "/agents/#{ERB::Util.url_encode(params[:agent_id].to_s)}/price-source"
  end

  # Only these fields, never the rest of the browser's body.
  def price_source_body
    { account_id: account_scope_id, type: params[:type].presence&.to_s, url: params[:url].presence&.to_s,
      refresh_hours: params[:refresh_hours].presence&.to_i }.compact
  end

  # The brain's refusals keep their HTTP status (the page tells a conflict from a field error).
  BRAIN_ERROR_STATUS = { 'owner_only' => :forbidden, 'invalid_settings' => :bad_request,
                         'version_conflict' => :conflict, 'not_live_ready' => :unprocessable_entity,
                         'brain_unreachable' => :bad_gateway }.freeze

  def render_brain(res)
    res = {} unless res.is_a?(Hash)
    status = BRAIN_ERROR_STATUS[res['error'].to_s]
    # A FastAPI HTTPException ({detail} only): a refused request.
    status ||= :bad_request if res.key?('detail') && !res.key?('ok')
    render json: res, status: status || :ok
  end

  def ensure_owner
    render json: { ok: false, error: 'owner_only' }, status: :forbidden unless owner?
  end

  # Who made the change, for the brain's audit log (A6).
  def actor_label
    "#{Current.user&.id}:#{Current.user&.email}"
  end

  def unsafe(value)
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
  end

  # Always the workspace of the URL the member was authorised for, never a value from the body.
  def account_scope_id
    Current.account.id
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end

  # Every request is signed for the URL account (H1); see Tolzar::BrainClient.sign.
  def post_to_brain(path, body)
    uri = Tolzar::BrainClient.uri(path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 130
    http.open_timeout = 5
    req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    req.body = body.to_json                              # before sign: v2 signs the exact body
    Tolzar::BrainClient.sign(req, account_scope_id)
    req['X-Tolzar-Actor'] = actor_label
    res = http.request(req)
    JSON.parse(res.body)
  rescue StandardError => e
    # The class only: never the request body (it may carry api_key / api_secret / account_sid).
    Rails.logger.warn("tolzar brain POST #{path} error: #{e.class}")
    { ok: false, error: 'brain_unreachable', reply: "The brain is not reachable right now (#{e.class})." }
  end

  def get_from_brain(path)
    uri = Tolzar::BrainClient.uri(path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 30
    http.open_timeout = 5
    req = Net::HTTP::Get.new(uri.request_uri)
    Tolzar::BrainClient.sign(req, account_scope_id)
    req['X-Tolzar-Actor'] = actor_label
    JSON.parse(http.request(req).body)
  rescue StandardError => e
    Rails.logger.warn("tolzar brain GET #{path.split('?').first} error: #{e.class}")
    { ok: false, error: 'brain_unreachable', agents: [], default_id: nil }
  end
end
