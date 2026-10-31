# Tolzar booking-system webhook (TOLZAR-BOOKING-DOCUMENTS-PLAN-2026-10-31.md §4 step 5): the external booking system
# tells Tolzar a booking was confirmed, paid, its voucher sent, or cancelled. Signed like Tolzar's own outgoing
# webhooks: X-Tolzar-Timestamp + X-Tolzar-Signature "sha256=" + HMAC-SHA256(secret, "#{ts}.#{raw body}"), the secret
# derived per connector (Tolzar::WebhookToken) and shown to the owner only. Within 5 minutes, each event once.
# Effects stay inside Tolzar: the contact's stage (confirmed / paid -> the won stage, cancelled -> the lost stage,
# only moving forward from earlier stages) and an activity line in the conversation. Nothing is sent to anyone.
class Tolzar::BookingHook
  Refused = Class.new(StandardError)

  EVENTS = %w[booking.confirmed booking.paid voucher.sent booking.cancelled].freeze
  MAX_SKEW = 5.minutes

  def self.secret(connector)
    Tolzar::WebhookToken.derive('booking', connector.id)
  end

  def self.verify!(connector, timestamp:, signature:, body:, now: Time.current)
    ts = Integer(timestamp.to_s, exception: false)
    raise Refused, 'stale' if ts.nil? || (now.to_i - ts).abs > MAX_SKEW.to_i

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret(connector), "#{ts}.#{body}")}"
    raise Refused, 'signature' unless Tolzar::WebhookToken.match?(expected, signature)
  end

  def initialize(connector, payload)
    @connector = connector
    @account = connector.account
    @payload = payload.to_h.with_indifferent_access
  end

  # => :done | :duplicate | :ignored
  def perform
    event = @payload[:event].to_s
    raise Refused, 'unknown event' unless EVENTS.include?(event)

    id = @payload[:id].to_s.presence || "#{event}:#{@payload[:voucher_no]}:#{@payload[:status]}"
    return :duplicate unless Redis::Alfred.set("tolzar:booking_hook:#{@connector.id}:#{Digest::SHA256.hexdigest(id)}", '1',
                                               nx: true, ex: 7.days.to_i)

    contact = find_contact
    conversation = find_conversation(contact)
    return :ignored if contact.nil? && conversation.nil?

    move_stage(contact || conversation.contact, event)
    note(conversation, event) if conversation
    :done
  end

  private

  def find_contact
    id = @payload[:tolzar_contact_id].presence
    @account.contacts.find_by(id: id) if id
  end

  def find_conversation(contact)
    display = @payload[:tolzar_conversation_id].presence
    conv = @account.conversations.find_by(display_id: display) if display
    conv || contact&.conversations&.order(last_activity_at: :desc)&.first
  end

  def move_stage(contact, event)
    stages = Tolzar::PipelineSettings.stage_keys(@account)
    won, lost = stages.last(2)
    target = event == 'booking.cancelled' ? lost : (won if %w[booking.confirmed booking.paid].include?(event))
    return if target.nil? || contact.nil?

    attr = Tolzar::PipelineSettings::STAGE_ATTRIBUTE
    attrs = (contact.custom_attributes || {}).dup
    current = attrs[attr]
    # Forward only: a won or lost contact is not moved by a later event of the other kind.
    return if [won, lost].include?(current) && current != target

    attrs[attr] = target
    attrs['booking_ref'] = @payload[:voucher_no].to_s.first(40) if @payload[:voucher_no].present?
    contact.update!(custom_attributes: attrs)
  end

  def note(conversation, event)
    words = { 'booking.confirmed' => 'confirmed', 'booking.paid' => 'paid', 'voucher.sent' => 'voucher sent',
              'booking.cancelled' => 'cancelled' }
    balance = @payload[:balance].present? ? " (balance #{@payload[:currency]} #{@payload[:balance]})".squeeze(' ') : ''
    conversation.messages.create!(account_id: @account.id, inbox_id: conversation.inbox_id, message_type: :activity,
                                  content: "Booking system: #{@payload[:voucher_no].presence || 'booking'} #{words[event]}#{balance}".first(300))
  end
end
