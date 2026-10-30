# Tolzar: "send" on a newsletter. Freezes the issue (status sending), queues one delivery per eligible user
# (the unique (newsletter, user) index makes a second run a no-op) and starts the batch job. Refused unless
# NEWSLETTER_ENABLED=true: nothing reaches a real inbox until the owner's DNS and Postal exist and he says so.
class Tolzar::NewsletterSendJob < ApplicationJob
  queue_as :low

  def perform(newsletter_id)
    raise 'NEWSLETTER_ENABLED is not true' unless self.class.enabled?

    newsletter = Tolzar::Newsletter.find(newsletter_id)
    return unless newsletter.draft?

    newsletter.update!(status: 'sending', sending_started_at: Time.current)
    domain = ENV.fetch('NEWSLETTER_SMTP_DOMAIN')
    users = newsletter.audience
    users.each_slice(500) do |slice|
      now = Time.current
      rows = slice.map do |user|
        { newsletter_id: newsletter.id, user_id: user.id, email: user.email, status: 'queued',
          message_id: "tolzar-nl-#{newsletter.id}-#{user.id}-#{SecureRandom.hex(6)}@#{domain}", created_at: now, updated_at: now }
      end
      Tolzar::NewsletterDelivery.insert_all(rows, unique_by: [:newsletter_id, :user_id])
    end
    newsletter.update!(recipients_count: newsletter.deliveries.count)
    Tolzar::NewsletterBatchJob.perform_later(newsletter.id)
  end

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('NEWSLETTER_ENABLED', 'false'))
  end
end
