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
  # The brain verifies the state by itself (signed, one-time, 15 min; the account and the user
  # were bound when the link was made) and answers with the account it verified. That answer is
  # the only source of the account here: never the state string or any request param.
  def callback
    res = Tolzar::BrainClient.post('/meta/callback', { code: params[:code].to_s, state: params[:state].to_s,
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
