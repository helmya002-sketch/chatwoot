# Tolzar: one newsletter issue to one user. The (newsletter, user) pair is unique, so queueing an issue twice
# never mails anyone twice; a batch claims a row by moving it from queued to sending in one UPDATE.
class Tolzar::NewsletterDelivery < ApplicationRecord
  self.table_name = 'tolzar_newsletter_deliveries'

  STATUSES = %w[queued sending sent failed skipped bounced].freeze

  belongs_to :newsletter, class_name: 'Tolzar::Newsletter', inverse_of: :deliveries
  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :queued, -> { where(status: 'queued') }

  # Deliveries handed to the SMTP server in the last 24 hours, over every issue: the warm-up cap counts these.
  def self.sent_in_last_day(now = Time.current)
    where(status: %w[sent bounced]).where(sent_at: (now - 24.hours)..now).count
  end

  # true when this process won the row (another batch may be looking at the same id).
  def claim!
    self.class.where(id: id, status: 'queued').update_all(status: 'sending', updated_at: Time.current) == 1
  end
end
