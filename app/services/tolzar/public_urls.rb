# Tolzar (readiness ranking #4): the address customers copy into their own websites. TOLZAR_WIDGET_BASE_URL
# (e.g. https://app.tolzar.com, a second hostname of the same app) is used for the website widget snippet,
# the help-centre portal's widget and the widget config's api_host, so no customer embeds the operator's
# FRONTEND_URL. Unset: FRONTEND_URL, as before. Channel webhooks and OAuth callbacks (Meta, Telegram, SMS,
# WhatsApp, LINE, Twilio, Slack, Linear, SSO) deliberately stay on FRONTEND_URL.
module Tolzar::PublicUrls
  module_function

  def widget_base
    (ENV['TOLZAR_WIDGET_BASE_URL'].presence || ENV.fetch('FRONTEND_URL', '')).to_s.chomp('/')
  end
end
