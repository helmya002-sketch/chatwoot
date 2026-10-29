# frozen_string_literal: true

# Tolzar: the few Graph API calls a workspace's own Meta app makes for a listen-only Facebook Page
# (with its linked Instagram account). Reads the page with the token the Owner pasted, and subscribes
# or unsubscribes THIS app to the page. Nothing here sends a message or changes a page setting.
# Every call carries appsecret_proof for the workspace's app, so it also works when the app requires it.
module Tolzar::MetaGraph
  VERSION = 'v26.0'
  BASE = "https://graph.facebook.com/#{VERSION}".freeze
  # Webhook fields for the page: messages and echoes (staff replies from Business Suite), postbacks,
  # standby (messages while another app is the page's responder) and feed (page post comments).
  PAGE_FIELDS = %w[messages message_echoes messaging_postbacks standby feed].freeze

  class Error < StandardError; end

  module_function

  def page(page_id, token, app_secret)
    get("/#{page_id}", { fields: 'id,name,access_token,instagram_business_account{id,username}' }, token, app_secret)
  end

  def subscribe(page_id, page_token, app_secret)
    request(Net::HTTP::Post, "/#{page_id}/subscribed_apps", { subscribed_fields: PAGE_FIELDS.join(',') },
            page_token, app_secret)
  end

  # The app-level webhook fields (the app dashboard's Webhooks section). Without them Meta sends
  # nothing, even with the page subscribed. Set with the app access token (app id|secret), which never
  # leaves the server; Meta checks the callback with a verify request (Tolzar::MetaHookController).
  APP_OBJECTS = {
    'page' => PAGE_FIELDS,
    'instagram' => %w[messages comments]
  }.freeze

  def subscribe_app(meta_app)
    token = "#{meta_app.app_id}|#{meta_app.app_secret}"
    APP_OBJECTS.each do |object, fields|
      request(Net::HTTP::Post, "/#{meta_app.app_id}/subscriptions",
              { object: object, callback_url: meta_app.webhook_url, verify_token: meta_app.verify_token,
                fields: fields.join(',') }, token, meta_app.app_secret)
    end
  end

  # The Instagram account linked to the page needs its own subscription to our app (with the page
  # token), or its comments never arrive.
  IG_FIELDS = %w[messages comments].freeze

  def subscribe_instagram(ig_user_id, page_token, app_secret)
    request(Net::HTTP::Post, "/#{ig_user_id}/subscribed_apps", { subscribed_fields: IG_FIELDS.join(',') },
            page_token, app_secret)
  end

  def unsubscribe(page_id, page_token, app_secret)
    request(Net::HTTP::Delete, "/#{page_id}/subscribed_apps", {}, page_token, app_secret)
  end

  def get(path, query, token, app_secret)
    request(Net::HTTP::Get, path, query, token, app_secret)
  end

  def proof(token, app_secret)
    OpenSSL::HMAC.hexdigest('SHA256', app_secret.to_s, token.to_s)
  end

  # The token goes in the Authorization header, never in the URL (URLs end up in logs and error
  # trackers). A POST carries its fields form-encoded in the body; GET and DELETE in the query.
  def request(klass, path, params, token, app_secret)
    uri = URI("#{BASE}#{path}")
    fields = params.merge(appsecret_proof: proof(token, app_secret))
    uri.query = URI.encode_www_form(fields) unless klass == Net::HTTP::Post
    req = klass.new(uri)
    req['Authorization'] = "Bearer #{token}"
    req.set_form_data(fields) if klass == Net::HTTP::Post
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 15
    res = http.request(req)
    body = JSON.parse(res.body.presence || '{}')
    raise Error, body.dig('error', 'message').to_s.first(200).presence || "Meta answered #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    body
  rescue JSON::ParserError
    raise Error, 'Meta sent an unreadable answer'
  end
end
