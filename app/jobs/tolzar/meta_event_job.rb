# Tolzar: one Messenger or Instagram messaging event of a workspace's own Meta app, written into the
# ONE listen-only page channel Tolzar::MetaHookRouter matched for that workspace. Chatwoot's own
# Webhooks::FacebookEventsJob / InstagramEventsJob look the page up across every account (by page id
# or Instagram id), so the same page connected in two workspaces would get both sets of DMs: this job
# never does a global lookup. Same Redis mutex keys as Chatwoot's jobs; a repeated delivery (same mid)
# adds nothing.
class Tolzar::MetaEventJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  def perform(channel_id, kind, item)
    channel = Channel::FacebookPage.find_by(id: channel_id, tolzar_listen_only: true)
    return if channel.blank? || channel.inbox.blank?

    kind == 'instagram' ? instagram(channel, item) : messenger(channel, item)
  end

  private

  def messenger(channel, item)
    response = ::Integrations::Facebook::MessageParser.new(item)
    return if response.echo? && response.sent_from_chatwoot_app?

    key = format(::Redis::Alfred::FACEBOOK_MESSAGE_MUTEX, sender_id: response.sender_id, recipient_id: response.recipient_id)
    with_lock(key) do
      next if response.identifier.present? && channel.inbox.messages.exists?(source_id: response.identifier)

      ::Messages::Facebook::MessageBuilder.new(response, channel.inbox, outgoing_echo: response.echo?).perform
    end
  end

  def instagram(channel, item)
    messaging = JSON.parse(item).with_indifferent_access
    return unless messaging.key?(:message) || messaging.key?(:postback) || messaging.key?(:read)

    contact_id = messaging.dig(:message, :is_echo) ? messaging.dig(:recipient, :id) : messaging.dig(:sender, :id)
    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: contact_id, ig_account_id: channel.instagram_id)
    with_lock(key, 3.seconds) { instagram_event(channel, messaging) }
  end

  def instagram_event(channel, messaging)
    if messaging.key?(:read)
      ::Instagram::ReadStatusService.new(params: messaging, channel: channel).perform
      return
    end
    if messaging.key?(:postback)
      messaging = messaging.merge(message: { mid: messaging.dig(:postback, :mid), text: messaging.dig(:postback, :title) })
    end
    mid = messaging.dig(:message, :mid)
    return if mid.present? && channel.inbox.messages.exists?(source_id: mid)

    ::Instagram::Messenger::MessageText.new(messaging, channel).perform
  end
end
