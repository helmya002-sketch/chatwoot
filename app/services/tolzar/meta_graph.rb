# frozen_string_literal: true

# Tolzar: the few Graph API calls a workspace's own Meta app makes for a listen-only Facebook Page
# (with its linked Instagram account). Reads the page with the token the Owner pasted, and subscribes
# or unsubscribes THIS app to the page. Nothing here sends a message or changes a page setting.
# Every call carries appsecret_proof for the workspace's app, so it also works when the app requires it.
module Tolzar::MetaGraph
  VERSION = 'v21.0'
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

  def unsubscribe(page_id, page_token, app_secret)
    request(Net::HTTP::Delete, "/#{page_id}/subscribed_apps", {}, page_token, app_secret)
  end

  def get(path, query, token, app_secret)
    request(Net::HTTP::Get, path, query, token, app_secret)
  end

  def proof(token, app_secret)
    OpenSSL::HMAC.hexdigest('SHA256', app_secret.to_s, token.to_s)
  end

  def request(klass, path, params, token, app_secret)
    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(params.merge(access_token: token, appsecret_proof: proof(token, app_secret)))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 15
    res = http.request(klass.new(uri))
    body = JSON.parse(res.body.presence || '{}')
    raise Error, body.dig('error', 'message').to_s.first(200).presence || "Meta answered #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    body
  rescue JSON::ParserError
    raise Error, 'Meta sent an unreadable answer'
  end
end
