# Tolzar: the webhook of a workspace's own Meta app (Tolzar::MetaApp), PUBLIC because Meta calls it.
#   GET  /tolzar/meta/hook/:webhook_token  the verify handshake (hub.verify_token -> hub.challenge)
#   POST /tolzar/meta/hook/:webhook_token  events, signed by Meta with THAT app's secret
# An unknown token is a 404 and a bad signature a 403; nothing is parsed before the signature passes.
# Events only reach this workspace's listen-only Facebook Page inboxes (Tolzar::MetaHookRouter).
class Tolzar::MetaHookController < ActionController::API
  def verify
    app = meta_app
    ok = app && params['hub.mode'] == 'subscribe' && app.valid_verify_token?(params['hub.verify_token'])
    return head(:not_found) unless ok

    render plain: params['hub.challenge'].to_s.first(200)
  end

  def events
    app = meta_app
    return head(:not_found) if app.blank?

    raw = request.raw_post
    return head(:forbidden) unless app.valid_signature?(raw, request.headers['X-Hub-Signature-256'])

    Tolzar::MetaHookRouter.new(app, JSON.parse(raw)).perform
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def meta_app
    token = params[:webhook_token].to_s
    return nil unless token.match?(/\A\h{32}\z/)

    Tolzar::MetaApp.find_by(webhook_token: token)
  end
end
