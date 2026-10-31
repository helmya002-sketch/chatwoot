# Tolzar briefing bar (the full-width greeting line above the app): what needs this person now, from the
# conversations they may open (Conversations::PermissionFilterService: administrators all, agents their inboxes).
#   hot  open conversations whose contact's lead score (the brain's `tolzar_lead_score`) is >= HOT_SCORE; the top
#        LIMIT by score, and how many there are
# For TOLZAR_TOPBAR_ACCOUNTS workspaces (round 4, c62) also:
#   now  counts that each open a list: mine (open, assigned to me), waiting (open and unattended: Chatwoot's own
#        Unattended rule), unassigned (open, nobody), due_today (snoozed, waking before the end of today in the
#        viewer's time zone), bookings_today (when bookings are on: not cancelled, today within its dates)
#   ai   the AI's state as the brain reports it: off / shadow / live / unknown (view-only; cached for a minute)
# Read-only; nothing is estimated, so an empty list or a 0 really means none.
class Tolzar::Briefing
  HOT_SCORE = 70 # the same rule as the inbox (tolzarAttention.js HOT_SCORE)
  LIMIT = 5
  RAW = "(contacts.custom_attributes->>'tolzar_lead_score')".freeze
  # A score that is not a plain number counts as none (CASE, so the cast never sees text). No `?` in the regex: in a
  # where string Rails reads every `?` as a bind placeholder (batch gate: Arel::BindError).
  SCORE = "(CASE WHEN #{RAW} ~ '^[0-9]+([.][0-9]+){0,1}$' THEN #{RAW}::numeric END)".freeze
  AI_CACHE = 1.minute

  def self.topbar?(account_id)
    ENV.fetch('TOLZAR_TOPBAR_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def initialize(account, user, time_zone: nil)
    @account = account
    @user = user
    @zone = ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
  end

  def report
    scope = hot_scope
    rows = scope.reorder(Arel.sql("#{SCORE} DESC, conversations.last_activity_at DESC")).limit(LIMIT)
                .pluck(:display_id, 'contacts.name', Arel.sql(SCORE), Arel.sql("contacts.custom_attributes->>'tolzar_lead_hint'"))
    out = { hot_count: scope.count,
            hot: rows.map { |id, name, score, hint| { id: id, name: name.to_s, score: score.to_f.round, hint: hint.to_s.first(140) } } }
    out.merge!(now: now_counts, ai: ai_state) if self.class.topbar?(@account.id)
    out
  end

  private

  def visible
    Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
  end

  def hot_scope
    visible.open.joins(:contact).where("#{SCORE} >= :min", min: HOT_SCORE)
  end

  def now_counts
    open = visible.open
    counts = { mine: open.where(assignee_id: @user.id).count, waiting: open.unattended.count,
               unassigned: open.where(assignee_id: nil).count,
               due_today: visible.snoozed.where(snoozed_until: ..@zone.now.end_of_day).count }
    counts[:bookings_today] = bookings_today if Tolzar::Booking.enabled?(@account.id)
    counts
  end

  def bookings_today
    today = @zone.today
    Tolzar::Booking.where(account_id: @account.id).where.not(status: 'cancelled').between(today, today).count
  end

  # off: the kill switch is on, or no inbox is in shadow or live; live: any inbox live (shown as it is, never a
  # button); unknown: the brain did not answer.
  def ai_state
    Rails.cache.fetch("tolzar:briefing:ai:#{@account.id}", expires_in: AI_CACHE) do
      res = Tolzar::BrainClient.get('/workspace/settings', account_id: @account.id)
      next 'unknown' unless res.is_a?(Hash) && res['status'].to_i == 200

      modes = (res['inbox_modes'] || {}).values.map { |m| m.is_a?(Hash) ? m['mode'].to_s : m.to_s }
      if res['kill_switch_on'] then 'off'
      elsif modes.include?('live') then 'live'
      elsif modes.include?('shadow') then 'shadow'
      else 'off'
      end
    end
  rescue StandardError
    'unknown'
  end
end
