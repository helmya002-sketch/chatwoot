# Tolzar (readiness ranking #4): the address customers copy into their own websites. TOLZAR_WIDGET_BASE_URL
# (e.g. https://app.tolzar.com, a second hostname of the same app) is used for the website widget snippet,
# the help-centre portal's widget and the widget config's api_host, so no customer embeds the operator's
# FRONTEND_URL. Unset: FRONTEND_URL, as before. Channel webhooks and OAuth callbacks (Meta, Telegram, SMS,
# WhatsApp, LINE, Twilio, Slack, Linear, SSO) deliberately stay on FRONTEND_URL; TikTok follows TIKTOK_REDIRECT_BASE.
module Tolzar::PublicUrls
  module_function

  def widget_base
    (ENV['TOLZAR_WIDGET_BASE_URL'].presence || ENV.fetch('FRONTEND_URL', '')).to_s.chomp('/')
  end

  # The host TikTok sends the OAuth callback and its webhook to (TIKTOK_REDIRECT_BASE, e.g. https://app.tolzar.com:
  # the owner wants TikTok users to see Tolzar's domain). Unset: FRONTEND_URL, as before. It must match the
  # redirect URL registered in the TikTok app exactly.
  def tiktok_base
    (ENV['TIKTOK_REDIRECT_BASE'].presence || ENV.fetch('FRONTEND_URL', 'http://localhost:3000')).to_s.chomp('/')
  end

  # The dashboard's own origin (FRONTEND_URL), where the user is signed in.
  def dashboard_url_options
    uri = URI.parse(ENV.fetch('FRONTEND_URL', ''))
    return {} if uri.host.blank?

    { host: uri.host, protocol: uri.scheme, port: (uri.port unless uri.port == uri.default_port) }.compact
  rescue URI::InvalidURIError
    {}
  end
end
