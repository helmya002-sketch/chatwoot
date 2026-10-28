class Twilio::CallbackController < ApplicationController
  include TwilioSignatureVerification
  before_action :verify_twilio_signature!

  def create
    Webhooks::TwilioEventsJob.perform_later(permitted_params.to_unsafe_hash)

    head :no_content
  end

  private

  # The channel Twilio::IncomingMessageService will use.
  def twilio_signature_channel = twilio_channel_for(:To)

  def permitted_params # rubocop:disable Metrics/MethodLength
    params.permit(
      :ApiVersion,
      :SmsSid,
      :From,
      :ToState,
      :ToZip,
      :AccountSid,
      :MessageSid,
      :OriginalRepliedMessageSid,
      :FromCountry,
      :ToCity,
      :FromCity,
      :To,
      :FromZip,
      :Body,
      :ToCountry,
      :FromState,
      *Array.new(10) { |i| :"MediaUrl#{i}" },
      *Array.new(10) { |i| :"MediaContentType#{i}" },
      :MessagingServiceSid,
      :NumMedia,
      :Latitude,
      :Longitude,
      :MessageType,
      :ProfileName,
      :ExternalUserId,
      :ParentExternalUserId,
      :ProfileUsername,
      :Username,
      :ReferralBody,
      :ReferralHeadline,
      :ReferralSourceId,
      :ReferralSourceType,
      :ReferralSourceUrl,
      :ReferralMediaId,
      :ReferralMediaContentType,
      :ReferralMediaUrl,
      :ReferralNumMedia,
      :ReferralCtwaClid
    )
  end
end
