# frozen_string_literal: true

# M5 (full-sec): a per-channel webhook secret derived from the app's secret_key_base, so no
# column or migration is needed and it never leaves the server except to the provider it is
# registered with (Telegram's secret_token, Bandwidth's callback password).
module Tolzar::WebhookToken
  module_function

  def derive(purpose, id)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base.to_s, "tolzar-webhook:#{purpose}:#{id}")
  end

  def match?(expected, given)
    given = given.to_s
    expected.present? && given.present? && ActiveSupport::SecurityUtils.secure_compare(expected, given)
  end
end
