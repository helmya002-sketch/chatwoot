# Tolzar: the app as the OAuth2 provider of ONE client, the community forum (Apache Answer), so only Tolzar users
# can sign in there and the forum has no registration of its own (owner-approved plan, 30 Oct 2026).
#   GET  /tolzar/oauth/authorize  authorization-code flow; the signed-in dashboard user is read from the dashboard's
#                                 own session cookie and checked with devise_token_auth; first-party, no consent page
#   POST /tolzar/oauth/token      code -> access token (client secret required, code single-use, 60 s)
#   GET  /tolzar/oauth/userinfo   Bearer access token -> id, username, name, email, avatar
# One client, configured by env: TOLZAR_FORUM_OAUTH_CLIENT_ID / _CLIENT_SECRET / _REDIRECT_URI (exact match).
# Built in (no provider gem) because it is one first-party client and three endpoints; codes live in Redis, access
# tokens are signed, short-lived and only open userinfo.
class Tolzar::ForumOauthController < ActionController::Base
  skip_forgery_protection
  layout false

  CODE_TTL = 60.seconds
  TOKEN_TTL = 10.minutes
  TOKEN_PURPOSE = :tolzar_forum_userinfo

  def authorize
    return render(:error, status: :bad_request) unless valid_authorize_request?

    @user = dashboard_user
    return render(:sign_in, status: :unauthorized) if @user.nil?
    return render(:not_eligible, status: :forbidden) unless eligible?(@user)

    code = SecureRandom.urlsafe_base64(32)
    Redis::Alfred.set(code_key(code), @user.id.to_s, ex: CODE_TTL.to_i)
    redirect_to "#{redirect_uri}#{redirect_uri.include?('?') ? '&' : '?'}#{{ code: code, state: params[:state] }.compact.to_query}",
                allow_other_host: true
  end

  def token
    return render(json: { error: 'invalid_client' }, status: :unauthorized) unless valid_client?
    return render(json: { error: 'unsupported_grant_type' }, status: :bad_request) unless params[:grant_type] == 'authorization_code'
    return render(json: { error: 'invalid_grant' }, status: :bad_request) unless params[:redirect_uri] == redirect_uri

    user_id = Redis::Alfred.with { |conn| conn.getdel(code_key(params[:code].to_s)) }
    user = User.find_by(id: user_id) if user_id
    return render(json: { error: 'invalid_grant' }, status: :bad_request) if user.nil? || !eligible?(user)

    access_token = verifier.generate(user.id, purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
    response.headers['Cache-Control'] = 'no-store'
    render json: { access_token: access_token, token_type: 'Bearer', expires_in: TOKEN_TTL.to_i }
  end

  def userinfo
    bearer = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    user = User.find_by(id: verifier.verified(bearer.to_s, purpose: TOKEN_PURPOSE)) if bearer
    return head(:unauthorized) if user.nil? || !eligible?(user)

    render json: { id: user.id.to_s, sub: user.id.to_s, username: "u#{user.id}", name: user.display_name.presence || user.name,
                   email: user.email, email_verified: true, picture: user.avatar_url.presence }
  end

  private

  def valid_authorize_request?
    params[:response_type] == 'code' &&
      ActiveSupport::SecurityUtils.secure_compare(params[:client_id].to_s, client_id) &&
      params[:redirect_uri].to_s == redirect_uri
  end

  def valid_client?
    id, secret = ActionController::HttpAuthentication::Basic.user_name_and_password(request) if request.authorization.to_s.start_with?('Basic ')
    id ||= params[:client_id]
    secret ||= params[:client_secret]
    ActiveSupport::SecurityUtils.secure_compare(id.to_s, client_id) &&
      ActiveSupport::SecurityUtils.secure_compare(secret.to_s, ENV.fetch('TOLZAR_FORUM_OAUTH_CLIENT_SECRET'))
  end

  # The dashboard keeps its devise_token_auth credentials in this cookie (app/javascript/dashboard/api/auth.js).
  def dashboard_user
    info = JSON.parse(cookies['cw_d_session_info'].to_s)
    user = User.find_by(uid: info['uid'].to_s)
    user if user&.valid_token?(info['access-token'].to_s, info['client'].to_s)
  rescue JSON::ParserError
    nil
  end

  # Tolzar users only: a confirmed user with at least one workspace (trial workspaces included).
  def eligible?(user)
    user.confirmed? && user.account_users.exists?
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
