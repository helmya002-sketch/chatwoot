# Tolzar: one verified Postal webhook event for a newsletter message.
#   MessageBounced                     a bounce came back: hard, the user is suppressed
#   MessageDeliveryFailed (HardFail)   the receiving server refused it for good: hard, suppressed
#   MessageDeliveryFailed (SoftFail)   a temporary refusal: soft; the 2nd within 30 days pauses the user
#   anything else                      ignored (Postal also reports sent, delayed, held, link clicks)
# Postal has no spam-complaint event; complaints reach abuse@ and a super admin suppresses the user by hand
# (reason "complaint") on the newsletter page.
class Tolzar::NewsletterBounceService
  def initialize(event)
    @event = event
  end

  def perform
    delivery = Tolzar::NewsletterDelivery.find_by(message_id: message_id) if message_id.present?
    return if delivery.nil?

    case kind
    when :hard
      delivery.update!(status: 'bounced', error: kind.to_s)
      Tolzar::NewsletterRecipient.suppress!(delivery.user_id, 'hard_bounce')
    when :soft
      delivery.update!(error: 'soft_bounce')
      Tolzar::NewsletterRecipient.soft_bounce!(delivery.user_id)
    end
  end

  private

  def payload
    @event['payload'] || {}
  end

  # MessageBounced carries the original message; MessageDeliveryFailed carries the message itself.
  def message_id
    msg = payload['original_message'] || payload['message'] || {}
    msg['message_id'].to_s.delete('<>').presence
  end

  def kind
    case @event['event']
    when 'MessageBounced' then :hard
    when 'MessageDeliveryFailed' then payload['status'] == 'HardFail' ? :hard : :soft
    end
  end
end
