# Tolzar: PUBLIC endpoints Meta calls for "Connect Facebook & Instagram" (per workspace).
#   GET  /tolzar/meta/callback       the OAuth redirect: code + signed state go to the brain,
#                                    which checks the state (one-time, 15 min, HMAC) and stores
#                                    the workspace's page tokens encrypted; then back to Settings.
#   POST /tolzar/meta/data_deletion  Meta's data-deletion callback (signed_request).
#   GET  /tolzar/meta/deletion       the status page Meta links the user to.
#   GET  /tolzar/meta/error          neutral page when a connect did not complete.
# Nothing here writes to Meta; read scopes only. Brain calls are signed (H1) with no member account (0):
# the brain trusts only its own proof here (the HMAC state, Meta's signed_request, the deletion code).
class Tolzar::MetaController < ActionController::API
  include ActionController::Cookies

  BIND_COOKIE = 'tolzar_meta_bind'

  # The brain verifies the state (signed, one-time, 15 min; the account and the user were bound
  # when the link was made) AND that this browser started it: we send sha256 of the
  # tolzar_meta_bind cookie set at connect-start and the brain compares it with the one it stored.
  # No cookie: refused here, the brain is not called. The cookie is cleared either way. The brain's
  # answer is the only source of the account: never the state string or any request param.
  def callback
    bind = cookies[BIND_COOKIE].to_s
    cookies.delete(BIND_COOKIE, path: '/tolzar/meta', secure: true, httponly: true, same_site: :lax)
    return redirect_to('/tolzar/meta/error', allow_other_host: false) if bind.empty?

    res = Tolzar::BrainClient.post('/meta/callback', { code: params[:code].to_s, state: params[:state].to_s,
                                                       bind_hash: Digest::SHA256.hexdigest(bind),
                                                       error: params[:error].presence,
                                                       error_description: params[:error_description].presence }.compact)
    acct = res['ok'] == true ? res['account_id'].to_i : 0
    # Until the Settings -> Connections page ships, land on the dashboard with the result.
    return redirect_to("/app/accounts/#{acct}/dashboard?tolzar_meta=connected", allow_other_host: false) if acct.positive?

    redirect_to '/tolzar/meta/error', allow_other_host: false
  end

  # Neutral landing when a connect did not complete (no workspace is named or guessed).
  def failed
    render plain: 'Facebook & Instagram were not connected (the link expired, was already used, or Meta did not ' \
                  'finish). Open Tolzar (/app) and start Connect Facebook & Instagram again.'
  end

  def data_deletion
    res = Tolzar::BrainClient.post('/meta/data_deletion', { signed_request: params[:signed_request].to_s })
    return head(:bad_request) unless res['confirmation_code']

    render json: { url: res['url'], confirmation_code: res['confirmation_code'] }
  end

  def deletion
    res = Tolzar::BrainClient.get("/meta/deletion?code=#{CGI.escape(params[:code].to_s[0, 32])}")
    text = res['done'] ? "Deletion request #{res['code']}: done. Tolzar no longer holds any Facebook or Instagram data for it." \
                       : 'Unknown deletion request code.'
    render plain: text
  end
end
