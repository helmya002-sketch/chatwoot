# Tolzar: hands queued newsletter deliveries to the newsletter SMTP server in small batches, at the warm-up
# rate: at most NEWSLETTER_DAILY_CAP messages in any 24 hours over every issue (200 while the domain is new),
# NEWSLETTER_BATCH_SIZE per run, one run every NEWSLETTER_BATCH_INTERVAL seconds. When the day's cap is used up
# it waits an hour and looks again. Each delivery re-checks the user right before sending, so an unsubscribe
# or a bounce between queueing and sending is honoured.
class Tolzar::NewsletterBatchJob < ApplicationJob
  queue_as :low

  def perform(newsletter_id)
    newsletter = Tolzar::Newsletter.find(newsletter_id)
    return unless newsletter.status == 'sending'

    room = [daily_cap - Tolzar::NewsletterDelivery.sent_in_last_day, 0].max
    return self.class.set(wait: 1.hour).perform_later(newsletter.id) if room.zero? && newsletter.deliveries.queued.exists?

    newsletter.deliveries.queued.order(:id).limit([room, batch_size].min).each { |delivery| deliver(delivery) }

    if newsletter.deliveries.queued.exists?
      self.class.set(wait: batch_interval.seconds).perform_later(newsletter.id)
    else
      newsletter.update!(status: 'sent', sent_at: Time.current)
    end
  end

  private

  def deliver(delivery)
    return unless delivery.claim!

    if blocked?(delivery.user_id) || delivery.user.nil?
      delivery.update!(status: 'skipped')
      return
    end

    Tolzar::NewsletterMailer.issue(delivery).deliver_now
    delivery.update!(status: 'sent', sent_at: Time.current)
  rescue Net::SMTPFatalError, Net::SMTPSyntaxError => e
    # The server refused this one recipient for good: the others go on.
    delivery.update!(status: 'failed', error: e.class.name)
  rescue Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError
    # The server is busy or unreachable: this one goes back to the queue and the job is retried later.
    delivery.update!(status: 'queued')
    raise
  end

  def blocked?(user_id)
    Tolzar::NewsletterRecipient.blocked.exists?(user_id: user_id)
  end

  def daily_cap
    ENV.fetch('NEWSLETTER_DAILY_CAP', '200').to_i
  end

  def batch_size
    ENV.fetch('NEWSLETTER_BATCH_SIZE', '50').to_i
  end

  def batch_interval
    ENV.fetch('NEWSLETTER_BATCH_INTERVAL', '60').to_i
  end
end
