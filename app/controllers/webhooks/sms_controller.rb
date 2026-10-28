class Webhooks::SmsController < ActionController::API
  # M5 (full-sec): Bandwidth does not sign callbacks. A callback for a known channel must carry that
  # channel's webhook_token, as the HTTP Basic password (Bandwidth callbackPassword) or ?token=.
  # The channel checked is the one Webhooks::SmsEventsJob acts on (the event's `to`).
  before_action :verify_webhook_token!

  def process_payload
    Webhooks::SmsEventsJob.perform_later(event&.to_unsafe_hash)
    head :ok
  end

  private

  def event
    params['_json']&.first
  end

  def verify_webhook_token!
    to = event.respond_to?(:key?) ? event[:to] : nil
    channel = Channel::Sms.find_by(phone_number: to.to_s) if to.present?
    return if channel.blank?
    return if Tolzar::WebhookToken.match?(channel.webhook_token, given_token)

    Rails.logger.warn("[SMS] rejected webhook with a missing or invalid token for channel #{channel.id}")
    head :forbidden
  end

  def given_token
    if request.authorization.to_s.start_with?('Basic ')
      password = ActionController::HttpAuthentication::Basic.user_name_and_password(request).last
      return password if password.present?
    end
    params[:token].to_s
  end
end
