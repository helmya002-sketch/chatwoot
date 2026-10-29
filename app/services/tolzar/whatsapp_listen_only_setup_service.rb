# frozen_string_literal: true

# Connects a WhatsApp number to Tolzar in listen-only mode (Tolzar::ListenOnly): the business's own
# in-house Meta app (system-user token + app secret, entered by the workspace owner) is subscribed to
# a WABA that another provider already runs. Nothing about the number changes; the inbox only
# receives. Reads Meta once to check the ids and the token (Whatsapp::ManualSetupValidationService,
# GET only), creates the channel + inbox with every customer-facing auto-message off, then subscribes
# our app to the WABA (Whatsapp::WebhookSetupService, which in listen-only mode does nothing else).
class Tolzar::WhatsappListenOnlySetupService
  attr_reader :channel, :inbox, :webhook_error

  def initialize(account:, waba_id:, phone_number_id:, access_token:, app_secret:, inbox_name: nil)
    @account = account
    @waba_id = waba_id.to_s.strip
    @phone_number_id = phone_number_id.to_s.strip
    @access_token = access_token.to_s.strip
    @app_secret = app_secret.to_s.strip
    @inbox_name = inbox_name
  end

  def perform
    raise ArgumentError, 'The app secret is required (Meta signs every webhook with it)' if @app_secret.blank?

    preview = Whatsapp::ManualSetupValidationService.new(waba_id: @waba_id, phone_number_id: @phone_number_id,
                                                         access_token: @access_token).perform
    create_channel_and_inbox(preview)
    subscribe
    self
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/webhooks/whatsapp/#{channel.phone_number}"
  end

  private

  def create_channel_and_inbox(preview)
    ActiveRecord::Base.transaction do
      @channel = @account.whatsapp_channels.create!(
        phone_number: preview[:display_phone_number],
        provider: 'whatsapp_cloud',
        provider_config: {
          api_key: @access_token, phone_number_id: preview[:phone_number_id], business_account_id: preview[:waba_id],
          app_secret: @app_secret, source: Tolzar::ListenOnly::SOURCE, Tolzar::ListenOnly::KEY => true
        }
      )
      @inbox = @account.inboxes.create!(
        name: @inbox_name.to_s.strip.presence || "#{preview[:suggested_inbox_name]} (listen-only)",
        channel: @channel,
        greeting_enabled: false, working_hours_enabled: false, csat_survey_enabled: false, enable_email_collect: false
      )
    end
  end

  def subscribe
    setup = Whatsapp::WebhookSetupService.new(@channel, @waba_id, @access_token)
    setup.perform
    @webhook_error = setup.registration_error&.message
  end
end
