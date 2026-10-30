# Tolzar: a workspace's plan, trial and paid-until (billing v1; manual until XPay checkout, whose provider
# references are kept here). The state is computed, never stored, so a clock change cannot leave it stale:
#   trialing        plan trial, trial_ends_at in the future: everything works
#   active          a paid plan with paid_until (plus GRACE) in the future, or plan internal
#   paused          the trial ended, or the paid plan lapsed: read-only (the inbox stays visible, the AI is
#                   off, staff cannot reply or change settings); incoming messages are still stored
#   purge_scheduled paused for HOLD (30 days): the daily job purges the workspace (item C), audited
# Choosing a plan and a paid_until resumes at once. Workspaces created before billing v1 are "internal".
class Tolzar::Subscription < ApplicationRecord
  self.table_name = 'tolzar_subscriptions'

  PLANS = %w[trial starter team business internal].freeze
  PAID = %w[starter team business].freeze
  SEATS = { 'trial' => 5, 'starter' => 2, 'team' => 5, 'business' => 15, 'internal' => 1000 }.freeze
  CURRENCIES = %w[USD EGP].freeze
  TRIAL = 30.days
  GRACE = 3.days
  HOLD = 30.days

  belongs_to :account

  validates :plan, inclusion: { in: PLANS }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :seat_limit, numericality: { only_integer: true, greater_than: 0 }

  # The row for a workspace, created on first use: a new workspace starts a trial.
  def self.for(account, now = Time.current)
    find_by(account_id: account.id) ||
      create!(account: account, plan: 'trial', trial_ends_at: now + TRIAL, seat_limit: SEATS['trial'])
  rescue ActiveRecord::RecordNotUnique
    find_by!(account_id: account.id)
  end

  def state(now = Time.current)
    return 'purged' if purged_at
    return 'active' if plan == 'internal'
    return pause_state(now) if lapsed?(now)

    plan == 'trial' ? 'trialing' : 'active'
  end

  def paused?(now = Time.current)
    %w[paused purge_scheduled].include?(state(now))
  end

  def lapsed?(now = Time.current)
    if plan == 'trial'
      trial_ends_at.present? && trial_ends_at <= now
    else
      paid_until.blank? || paid_until + GRACE < now
    end
  end

  # When the pause started (stored once, the first time it is seen), and when the data hold ends.
  def mark_paused!(now = Time.current)
    return unless lapsed?(now) && paused_at.nil?

    update!(paused_at: now, purge_after: now + HOLD)
  end

  # Super Admin: a paid plan until a date (manual billing). Clears any pause at once.
  def activate!(plan:, paid_until:, by: nil, seat_limit: nil, currency: nil)
    update!(plan: plan, paid_until: paid_until, paused_at: nil, purge_after: nil, updated_by_id: by&.id,
            seat_limit: seat_limit || SEATS.fetch(plan), currency: currency || self.currency)
  end

  def extend_trial!(days:, by: nil)
    update!(trial_ends_at: [trial_ends_at, Time.current].compact.max + days.to_i.days,
            paused_at: nil, purge_after: nil, updated_by_id: by&.id)
  end

  def seats_left
    seat_limit - account.account_users.count
  end

  def view(now = Time.current)
    { plan: plan, state: state(now), trial_ends_at: trial_ends_at, paid_until: paid_until, paused_at: paused_at,
      purge_after: purge_after, seat_limit: seat_limit, seats_used: account.account_users.count, currency: currency }
  end

  private

  def pause_state(now)
    purge_after.present? && purge_after <= now ? 'purge_scheduled' : 'paused'
  end
end
