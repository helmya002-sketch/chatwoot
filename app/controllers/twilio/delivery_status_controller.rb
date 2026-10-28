class Twilio::DeliveryStatusController < ApplicationController
  include TwilioSignatureVerification
  before_action :verify_twilio_signature!

  def create
    Webhooks::TwilioDeliveryStatusJob.perform_later(permitted_params.to_unsafe_hash)

    head :no_content
  end

  private

  # The channel Twilio::DeliveryStatusService will use.
  def twilio_signature_channel = twilio_channel_for(:From)

  def permitted_params
    params.permit(
      :AccountSid,
      :From,
      :MessageSid,
      :MessagingServiceSid,
      :MessageStatus,
      :ErrorCode,
      :ErrorMessage
    )
  end
end
