# Tolzar: one newsletter issue to the app's own users (see the migration for the owner's decision). A draft is
# written and previewed by a super admin; "send" queues one delivery per eligible user and the batch job
# hands them to the newsletter SMTP server (Postal on news.<domain>) at the warm-up rate. Generic: nothing here
# names a business; the copy is the super admin's.
class Tolzar::Newsletter < ApplicationRecord
  self.table_name = 'tolzar_newsletters'

  STATUSES = %w[draft sending sent].freeze
  SUBJECT_MAX = 200
  BODY_MAX = 50_000

  has_many :deliveries, class_name: 'Tolzar::NewsletterDelivery', inverse_of: :newsletter, dependent: :delete_all

  validates :subject, presence: true, length: { maximum: SUBJECT_MAX }
  validates :body_markdown, presence: true, length: { maximum: BODY_MAX }
  validates :status, inclusion: { in: STATUSES }
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }, allow_nil: true
  validate :frozen_once_sending, on: :update

  before_validation { self.locale = locale.presence }

  def draft?
    status == 'draft'
  end

  # Users who receive this issue now: they use the app (a confirmed user with an email and at least one
  # workspace), have not opted out, are not suppressed, and match the language filter.
  def audience
    Tolzar::NewsletterAudience.new(locale: locale).users
  end

  def counts
    deliveries.group(:status).count
  end

  # Markdown to HTML with raw HTML in the body escaped (the body is written by a super admin, but a pasted
  # snippet must never become a script in hundreds of inboxes).
  def body_html
    CommonMarker.render_html(body_markdown.to_s, [:DEFAULT], [:table, :strikethrough, :autolink])
  end

  def body_text
    CommonMarker.render_doc(body_markdown.to_s, :DEFAULT, [:table, :strikethrough, :autolink]).to_plaintext
  end

  private

  def frozen_once_sending
    return if status_was == 'draft'
    return unless subject_changed? || body_markdown_changed? || locale_changed?

    errors.add(:base, 'is being sent or was sent and can no longer be edited')
  end
end
