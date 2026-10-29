# frozen_string_literal: true

# Tolzar listen-only WhatsApp inboxes (2026-10-29, Meta "option 2").
#
# A business keeps its existing WhatsApp provider (respond.io, often on Business-app coexistence)
# and ALSO subscribes its own in-house Meta app to the same WABA, so Tolzar receives customer
# messages natively while staff keep replying where they always did. Such an inbox must never act
# on the number or on the customer:
#   - connect = only POST /{waba}/subscribed_apps for our own app (WebhookSetupService): never
#     /register, never a phone-number-level callback override (that sits above every app's
#     webhook and is not provably per app);
#   - delete  = only DELETE our own app's WABA subscription, and only when no other inbox uses that
#     WABA (WebhookTeardownService): never clear a phone-level override, never /deregister;
#   - nothing reaches the customer: replies (SendReplyJob), templates, CSAT templates, contact-info
#     requests and calling settings are refused here and logged.
# The flag lives in the channel's provider_config (KEY); Tolzar::WhatsappListenOnlySetupService
# creates such inboxes. Generic: no business is named anywhere.
module Tolzar
  module ListenOnly
    KEY = 'tolzar_listen_only'
    SOURCE = 'tolzar_listen_only'
    BLOCKED_PROVIDER_METHODS = %i[send_message send_template create_csat_template delete_csat_template
                                  update_calling_status].freeze

    module_function

    def channel?(channel)
      return false unless channel.respond_to?(:provider_config)

      ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})[KEY]) == true
    end

    def inbox?(inbox)
      inbox.present? && channel?(inbox.channel)
    end

    def blocked(channel, what)
      Rails.logger.warn("[Tolzar listen-only] refused #{what} for whatsapp channel #{channel&.id}")
      nil
    end

    # Prepended to the WhatsApp Cloud provider (config/initializers/zz_tolzar_listen_only.rb):
    # every call that would send to a customer or change something at Meta stops here.
    module ProviderGuard
      BLOCKED_PROVIDER_METHODS.each do |name|
        define_method(name) do |*args, **kwargs, &block|
          return Tolzar::ListenOnly.blocked(whatsapp_channel, name) if Tolzar::ListenOnly.channel?(whatsapp_channel)

          super(*args, **kwargs, &block)
        end
      end
    end

    module ContactInfoGuard
      def perform(*args, **kwargs, &block)
        return Tolzar::ListenOnly.blocked(whatsapp_channel, :request_contact_info) if Tolzar::ListenOnly.channel?(whatsapp_channel)

        super
      end
    end

    module ChannelGuard
      def enable_voice_calling!
        raise 'A listen-only WhatsApp inbox cannot change calling settings at Meta' if Tolzar::ListenOnly.channel?(self)

        super
      end

      def disable_voice_calling!
        raise 'A listen-only WhatsApp inbox cannot change calling settings at Meta' if Tolzar::ListenOnly.channel?(self)

        super
      end
    end
  end
end
