# frozen_string_literal: true

# M5 (full-sec): Twilio signs every webhook with X-Twilio-Signature = Base64(HMAC-SHA1(auth token,
# full URL + each POST param name+value sorted by name)). A request for a known Twilio channel is
# rejected (403) when the signature is missing or does not match, so inbound customer messages and
# delivery statuses can't be spoofed. A request naming no known channel goes on as before (the job
# finds nothing and drops it).
#
# The signing key is the account's primary auth token. A channel set up with an API key stores the
# API key secret in auth_token, which Twilio does not sign with: such a channel is verified only when
# provider_config['webhook_auth_token'] holds the account auth token (otherwise logged, not checked).
module TwilioSignatureVerification
  extend ActiveSupport::Concern

  private

  def verify_twilio_signature!
    channel = twilio_signature_channel
    return if channel.blank?

    token = twilio_signing_token(channel)
    if token.blank?
      Rails.logger.warn("[TWILIO] signature not checked: channel #{channel.id} uses an API key and has no webhook_auth_token")
      return
    end
    return if twilio_signature_valid?(token)

    Rails.logger.warn("[TWILIO] rejected webhook with a missing or invalid signature for channel #{channel.id}")
    head :forbidden
  end

  def twilio_signing_token(channel)
    explicit = channel.provider_config.to_h['webhook_auth_token'].presence
    return explicit if explicit

    channel.api_key_sid.present? ? nil : channel.auth_token
  end

  def twilio_signature_valid?(token)
    signature = request.headers['X-Twilio-Signature'].to_s
    return false if signature.blank?

    validator = ::Twilio::Security::RequestValidator.new(token)
    body = request.request_parameters.to_h
    twilio_signed_urls.any? { |url| validator.validate(url, body, signature) }
  end

  # Behind a TLS-terminating proxy Rails may see http://; Twilio signed the URL it was given,
  # which is FRONTEND_URL + path.
  def twilio_signed_urls
    urls = [request.original_url]
    frontend = ENV.fetch('FRONTEND_URL', nil).to_s.chomp('/')
    urls << "#{frontend}#{request.fullpath}" if frontend.present?
    urls.uniq
  end

  def twilio_channel_for(number_param)
    sid = params[:MessagingServiceSid].presence
    channel = ::Channel::TwilioSms.find_by(messaging_service_sid: sid) if sid
    if channel.nil? && params[:AccountSid].present? && params[number_param].present?
      channel = ::Channel::TwilioSms.find_by(account_sid: params[:AccountSid], phone_number: params[number_param])
    end
    channel
  end
end
