# Tolzar: the app as the OAuth2 provider of ONE client, the community forum (Apache Answer), so only Tolzar users
# can sign in there and the forum has no registration of its own (owner-approved plan, 30 Oct 2026).
#   GET  /tolzar/oauth/authorize  checks the request, then shows "Continue as <name>" (an explicit click; never framed)
#   POST /tolzar/oauth/authorize  the click (Rails CSRF token): issues a code bound to the redirect URI and PKCE
#   POST /tolzar/oauth/token      code -> access token: client secret (constant-time), PKCE S256, code single-use
#                                 (GET + DEL in one MULTI), rate-limited per IP
#   GET  /tolzar/oauth/userinfo   Bearer access token -> id, username, display name, locale, email
# Security guard (Oracle, 30 Oct): exact redirect match, state passed through, codes stored only as SHA-256 hashes in
# Redis for 60 s, access tokens signed (never stored) for 10 min and good for userinfo only, frame-ancestors 'none'.
# One client, configured by env: TOLZAR_FORUM_OAUTH_CLIENT_ID / _CLIENT_SECRET / _REDIRECT_URI. PKCE S256 is
# always required: without it a client that does not check `state` is open to login CSRF (security review, 30 Oct),
# so a connector without PKCE must be patched, never this check relaxed. Impersonation sessions are refused.
# Built in (no provider gem): one first-party client and four endpoints; a gem would need a Gemfile.lock this
# machine cannot produce. Red-team spec: spec/tolzar/forum_oauth_spec.rb.
class Tolzar::ForumOauthController < ActionController::Base
  protect_from_forgery with: :exception
  skip_forgery_protection only: [:token, :userinfo] # server-to-server: the client secret / bearer token is the credential
  layout false

  CODE_TTL = 60.seconds
  TOKEN_TTL = 10.minutes
  TOKEN_PURPOSE = :tolzar_forum_userinfo
  TOKEN_LIMIT_PER_MINUTE = 60

  before_action :no_framing, only: [:authorize, :approve]

  def authorize
    return render(:error, status: :bad_request) unless valid_authorize_request?

    @user = dashboard_user
    return render(:sign_in, status: :unauthorized) if @user.nil?
    return render(:not_eligible, status: :forbidden) unless eligible?(@user)

    render :consent
  end

  def approve
    return render(:error, status: :bad_request) unless valid_authorize_request?

    user = dashboard_user
    return render(:sign_in, status: :unauthorized) if user.nil?
    return render(:not_eligible, status: :forbidden) unless eligible?(user)

    code = SecureRandom.urlsafe_base64(32)
    grant = { user_id: user.id, redirect_uri: redirect_uri, code_challenge: params[:code_challenge].to_s }
    Redis::Alfred.set(code_key(code), grant.to_json, ex: CODE_TTL.to_i)
    redirect_to "#{redirect_uri}#{redirect_uri.include?('?') ? '&' : '?'}#{{ code: code, state: params[:state] }.compact.to_query}",
                allow_other_host: true
  end

  def token
    return render(json: { error: 'slow_down' }, status: :too_many_requests) if token_rate_limited?
    return render(json: { error: 'invalid_client' }, status: :unauthorized) unless valid_client?
    return render(json: { error: 'unsupported_grant_type' }, status: :bad_request) unless params[:grant_type] == 'authorization_code'

    # Read and delete in one MULTI, so a code works once. Not GETDEL: Redis::Namespace (the $alfred pool) does not
    # namespace GETDEL and would look the code up under the wrong key (gate, 30 Oct).
    key = code_key(params[:code].to_s)
    raw, = Redis::Alfred.with do |conn|
      conn.multi do |tx|
        tx.get(key)
        tx.del(key)
      end
    end
    grant = raw ? JSON.parse(raw) : {}
    user = User.find_by(id: grant['user_id']) if grant['redirect_uri'] == params[:redirect_uri].to_s && pkce_ok?(grant)
    return render(json: { error: 'invalid_grant' }, status: :bad_request) if user.nil? || !eligible?(user)

    access_token = verifier.generate(user.id, purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    render json: { access_token: access_token, token_type: 'Bearer', expires_in: TOKEN_TTL.to_i }
  end

  # The minimum the forum needs: a stable id, a username that is not personal data, the display name, the language
  # and the email (Answer requires an email on every account; the forum never shows it).
  def userinfo
    bearer = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    user = User.find_by(id: verifier.verified(bearer.to_s, purpose: TOKEN_PURPOSE)) if bearer
    return head(:unauthorized) if user.nil? || !eligible?(user)

    response.headers['Cache-Control'] = 'no-store'
    render json: { id: user.id.to_s, username: forum_username(user), name: user.display_name.presence || user.name,
                   locale: Tolzar::NewsletterAudience.locale_for(user), email: user.email }
  end

  private

  def no_framing
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['Content-Security-Policy'] = "frame-ancestors 'none'"
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end

  def valid_authorize_request?
    params[:response_type] == 'code' &&
      ActiveSupport::SecurityUtils.secure_compare(params[:client_id].to_s, client_id) &&
      params[:redirect_uri].to_s == redirect_uri &&
      params[:code_challenge_method] == 'S256' && params[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)
  end

  def pkce_ok?(grant)
    challenge = grant['code_challenge'].to_s
    return false if challenge.blank?

    verifier_param = params[:code_verifier].to_s
    return false unless verifier_param.match?(/\A[A-Za-z0-9._~-]{43,128}\z/)

    computed = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier_param), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(computed, challenge)
  end

  def valid_client?
    if request.authorization.to_s.start_with?('Basic ')
      id, secret = ActionController::HttpAuthentication::Basic.user_name_and_password(request).map { |v| CGI.unescape(v.to_s) }
    end
    id ||= params[:client_id]
    secret ||= params[:client_secret]
    ActiveSupport::SecurityUtils.secure_compare(id.to_s, client_id) &&
      ActiveSupport::SecurityUtils.secure_compare(secret.to_s, ENV.fetch('TOLZAR_FORUM_OAUTH_CLIENT_SECRET'))
  end

  def token_rate_limited?
    Redis::RateLimit.new("tolzar:forum_oauth:token:#{request.remote_ip}", limit: TOKEN_LIMIT_PER_MINUTE, window: 1.minute).exceeded?
  end

  # The dashboard keeps its devise_token_auth credentials in this cookie (app/javascript/dashboard/api/auth.js).
  # A super admin impersonating a customer must never post on the public forum as that customer.
  def dashboard_user
    info = JSON.parse(cookies['cw_d_session_info'].to_s)
    return nil unless info.is_a?(Hash)

    client = info['client'].to_s
    user = User.find_by(uid: info['uid'].to_s)
    return nil unless user&.valid_token?(info['access-token'].to_s, client)

    user unless (user.tokens || {}).dig(client, 'impersonation')
  rescue JSON::ParserError
    nil
  end

  # Tolzar users only: a confirmed user of at least one active workspace (trial workspaces included).
  def eligible?(user)
    user.confirmed? && user.accounts.where(status: :active).exists?
  end

  def forum_username(user)
    "m#{OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "tolzar-forum:#{user.id}").first(12)}"
  end

  def code_key(code)
    "tolzar:forum_oauth:code:#{Digest::SHA256.hexdigest(code)}"
  end

  def verifier
    Rails.application.message_verifier(TOKEN_PURPOSE)
  end

  def client_id
    ENV.fetch('TOLZAR_FORUM_OAUTH_CLIENT_ID')
  end

  def redirect_uri
    ENV.fetch('TOLZAR_FORUM_OAUTH_REDIRECT_URI')
  end
end
