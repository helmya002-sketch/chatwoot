# Tolzar: PUBLIC endpoints Meta calls for "Connect Facebook & Instagram" (per workspace).
#   GET  /tolzar/meta/callback       the OAuth redirect: code + signed state go to the brain,
#                                    which checks the state (one-time, 15 min, HMAC) and stores
#                                    the workspace's page tokens encrypted; then back to Settings.
#   POST /tolzar/meta/data_deletion  Meta's data-deletion callback (signed_request).
#   GET  /tolzar/meta/deletion       the status page Meta links the user to.
# Nothing here writes to Meta; read scopes only. Brain calls are signed (H1) with no member account (0):
# the brain trusts only its own proof here (the HMAC state, Meta's signed_request, the deletion code).
class Tolzar::MetaController < ActionController::API
  def callback
    res = Tolzar::BrainClient.post('/meta/callback', { code: params[:code].to_s, state: params[:state].to_s,
                                                       error: params[:error].presence,
                                                       error_description: params[:error_description].presence }.compact)
    acct = res['account_id'].to_i
    acct = params[:state].to_s.split('.').first.to_i if acct.zero?
    result = res['ok'] ? 'connected' : 'error'
    # Until the Settings → Connections page ships, land on the dashboard with the result.
    redirect_to "/app/accounts/#{acct.positive? ? acct : 1}/dashboard?tolzar_meta=#{result}", allow_other_host: false
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
