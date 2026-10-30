# Tolzar: a user's newsletter state, kept only for users who opted out or were suppressed (no row = subscribed).
#   opted_out_at   the user's own one-click unsubscribe; honoured at once, undone only by the user
#   suppressed_at  a hard bounce, 2 soft bounces within 30 days, a complaint, or a super admin
# Transactional mail (password reset, invoices, security) never reads this: it is the newsletter's alone.
class Tolzar::NewsletterRecipient < ApplicationRecord
  self.table_name = 'tolzar_newsletter_recipients'

  SOFT_BOUNCE_WINDOW = 30.days
  SOFT_BOUNCE_LIMIT = 2
  REASONS = %w[hard_bounce soft_bounces complaint super_admin].freeze

  belongs_to :user, optional: true

  validates :user_id, uniqueness: true
  validates :suppression_reason, inclusion: { in: REASONS }, allow_nil: true

  scope :blocked, -> { where.not(opted_out_at: nil).or(where.not(suppressed_at: nil)) }

  def self.for(user_id)
    find_or_create_by!(user_id: user_id)
  rescue ActiveRecord::RecordNotUnique
    find_by!(user_id: user_id)
  end

  def self.opt_out!(user_id, now = Time.current)
    rec = self.for(user_id)
    rec.update!(opted_out_at: now) if rec.opted_out_at.nil?
    rec
  end

  def self.suppress!(user_id, reason, now = Time.current)
    rec = self.for(user_id)
    rec.update!(suppressed_at: now, suppression_reason: reason) if rec.suppressed_at.nil?
    rec
  end

  # A soft bounce: the second one inside 30 days pauses the user (suppressed, reason soft_bounces).
  def self.soft_bounce!(user_id, now = Time.current)
    rec = self.for(user_id)
    recent = Array(rec.soft_bounces).filter_map { |t| Time.zone.parse(t.to_s) rescue nil } # rubocop:disable Style/RescueModifier
                                    .select { |t| t > now - SOFT_BOUNCE_WINDOW }
    recent << now
    attrs = { soft_bounces: recent.map(&:iso8601) }
    attrs.merge!(suppressed_at: now, suppression_reason: 'soft_bounces') if recent.size >= SOFT_BOUNCE_LIMIT && rec.suppressed_at.nil?
    rec.update!(attrs)
    rec
  end

  # A super admin clears a suppression (never an opt-out: that is the user's choice).
  def unsuppress!
    update!(suppressed_at: nil, suppression_reason: nil, soft_bounces: [])
  end
end
