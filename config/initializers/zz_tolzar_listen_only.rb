# frozen_string_literal: true

# Tolzar listen-only WhatsApp inboxes: the outbound guards (app/services/tolzar/listen_only.rb).
# to_prepare so they survive code reloading in development; prepended last, so they wrap any
# Enterprise override of the same methods too.
Rails.application.config.to_prepare do
  {
    Whatsapp::Providers::WhatsappCloudService => Tolzar::ListenOnly::ProviderGuard,
    Whatsapp::Providers::WhatsappCloudContactInfoRequestService => Tolzar::ListenOnly::ContactInfoGuard,
    Channel::Whatsapp => Tolzar::ListenOnly::ChannelGuard
  }.each do |klass, guard|
    klass.prepend(guard) unless klass.ancestors.include?(guard)
  end
end
