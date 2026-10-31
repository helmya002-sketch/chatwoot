# Tolzar Control Center data (TOLZAR-APP-UI-REDESIGN-PLAN-2026-10-31.md phase 6): the overview figures and alerts,
# the onboarding funnel, the workspaces list and the system health page. Read-only: nothing here changes a record.
# Generic: no business names in code. Secret values are never read; an env-configured URL is fetched only by name.
class Tolzar::ControlCenter
  CACHE = 5.minutes
  BACKUP_MAX_AGE = 26.hours
  MIRROR_LAG_WARN = 15.minutes
  FUNNEL_WINDOW = 30.days
  STATES = %w[trialing active paused purge_scheduled purged].freeze

  def initialize(now: Time.current)
    @now = now
  end

  # --- Overview ------------------------------------------------------------------------------------------------

  def overview
    Rails.cache.fetch('tolzar:control_center:overview', expires_in: CACHE) do
      rows = subscriptions
      {
        workspaces: STATES.index_with { |s| rows.count { |_a, sub| sub.state(@now) == s } }
                          .merge('internal' => rows.count { |_a, sub| sub.plan == 'internal' }),
        users_today: User.where(last_sign_in_at: @now.beginning_of_day..).count,
        users_7d: User.where(last_sign_in_at: (@now - 7.days)..).count,
        conversations_today: Conversation.unscoped.where(created_at: @now.beginning_of_day..).count,
        conversations_7d: Conversation.unscoped.where(created_at: (@now - 7.days)..).count,
        trials_ending: trials_ending(rows),
        fair_use: fair_use(rows)
      }
    end
  end

  # Alerts are computed fresh (cheap): each is {level:, key:, detail:}.
  def alerts
    list = []
    missing = Tolzar::SuperAdminMfa.missing
    list << { level: :warning, key: 'superadmin_2fa', detail: missing.size } if missing.any?
    paused = subscriptions.select { |_a, sub| sub.paused?(@now) }
    list << { level: :warning, key: 'paused', detail: paused.size } if paused.any?
    over = overview[:fair_use].count { |row| row[:level] == 'over' }
    list << { level: :danger, key: 'fair_use_over', detail: over } if over.positive?
    backup = backup_status
    list << { level: :danger, key: 'backup_old', detail: backup[:age_hours].to_f.round } if backup[:stale]
    lag = mirror_lag
    list << { level: :warning, key: 'mirror_lag', detail: (lag / 60).round } if lag && lag > MIRROR_LAG_WARN
    list
  end

  # --- Onboarding funnel ---------------------------------------------------------------------------------------

  # Workspaces created in the window, and how many reached each step (each step counts those that also did the
  # step before it): signed up -> connected a channel -> got a first customer message -> sent a first reply.
  def funnel
    Rails.cache.fetch('tolzar:control_center:funnel', expires_in: CACHE) do
      ids = Account.where(created_at: (@now - FUNNEL_WINDOW)..).pluck(:id)
      channel = Inbox.where(account_id: ids).distinct.pluck(:account_id)
      incoming = Message.unscoped.where(account_id: channel, message_type: :incoming).distinct.pluck(:account_id)
      replied = Message.unscoped.where(account_id: incoming, message_type: :outgoing, private: false)
                       .distinct.pluck(:account_id)
      [['signed_up', ids.size], ['channel', channel.size], ['first_message', incoming.size], ['first_reply', replied.size]]
    end
  end

  # --- Workspaces ----------------------------------------------------------------------------------------------

  def workspaces(query: nil, state: nil)
    scope = Account.order(created_at: :desc)
    scope = scope.where('accounts.name ILIKE ?', "%#{Account.sanitize_sql_like(query)}%") if query.present?
    rows = workspace_rows(scope.limit(500).to_a)
    state.present? ? rows.select { |r| r[:state] == state } : rows
  end

  def workspace(account)
    sub = Tolzar::Subscription.find_by(account_id: account.id)
    {
      subscription: sub&.view(@now),
      fair_use: (account.internal_attributes || {})[Tolzar::FairUse::KEY],
      inboxes: account.inboxes.order(:id).map { |i| { id: i.id, name: i.name, channel: i.channel_type.to_s.demodulize } },
      members: account.account_users.includes(:user).order(:id).map do |au|
        { name: au.user&.name, email: au.user&.email, role: au.role, mfa: au.user&.otp_required_for_login? || false,
          last_sign_in_at: au.user&.last_sign_in_at }
      end,
      conversations_30d: Conversation.unscoped.where(account_id: account.id, created_at: (@now - 30.days)..).count,
      ai: ai_state(account)
    }
  end

  # The workspace's AI as the brain sees it (read-only): the kill switch, each inbox's mode (an inbox without an
  # entry is in shadow) and the agents. nil when the brain does not answer.
  def ai_state(account)
    settings = Tolzar::BrainClient.get('/workspace/settings', account_id: account.id)
    return unless settings['status'] == 200

    agents = Tolzar::BrainClient.get('/agents', account_id: account.id)
    modes = settings['inbox_modes'].is_a?(Hash) ? settings['inbox_modes'].transform_keys(&:to_s) : {}
    { kill_switch_on: settings['kill_switch_on'] == true,
      inbox_modes: modes.transform_values { |m| m.is_a?(Hash) ? m['mode'].to_s : m.to_s },
      agents: Array(agents['agents']).filter_map do |a|
        { name: a['name'].to_s.first(80), status: a['status'].to_s.first(20) } if a.is_a?(Hash)
      end }
  rescue StandardError
    nil
  end

  # --- AI safety: the kill switch and live inboxes of every workspace (read-only) -----------------------------

  AI_OVERVIEW_LIMIT = 100

  def ai_overview
    Rails.cache.fetch('tolzar:control_center:ai_overview', expires_in: CACHE) do
      Account.order(:id).limit(AI_OVERVIEW_LIMIT).map do |account|
        ai = ai_state(account)
        { id: account.id, name: account.name, known: !ai.nil?, kill_switch_on: ai&.dig(:kill_switch_on) || false,
          live_inboxes: (ai&.dig(:inbox_modes) || {}).count { |_id, mode| mode == 'live' }, agents: ai&.dig(:agents)&.size || 0 }
      end
    end
  end

  # --- Billing overview (billing v1 is manual until XPay; changes stay on the billing page) --------------------

  def billing_overview
    subs = Tolzar::Subscription.includes(:account).to_a
    soon = @now + 14.days
    {
      plans: subs.group_by(&:plan).transform_values(&:size),
      currencies: subs.select { |s| Tolzar::Subscription::PAID.include?(s.plan) }.group_by(&:currency).transform_values(&:size),
      renewals: subs.select { |s| Tolzar::Subscription::PAID.include?(s.plan) && s.paid_until&.between?(@now, soon) }
                    .sort_by(&:paid_until).map { |s| { id: s.account_id, name: s.account&.name, plan: s.plan, date: s.paid_until } },
      trials: subs.select { |s| s.plan == 'trial' && s.trial_ends_at&.between?(@now, soon) }
                  .sort_by(&:trial_ends_at).map { |s| { id: s.account_id, name: s.account&.name, plan: s.plan, date: s.trial_ends_at } },
      enforced: Tolzar::Subscription.enforced?
    }
  end

  # --- People and 2FA ------------------------------------------------------------------------------------------

  # Every user with their workspaces and roles, their 2FA state and last sign-in. Administrators and super admins
  # without 2FA come first, so the risk is at the top.
  def people(only_missing: false)
    users = User.includes(account_users: :account).order(:email).limit(1000).to_a
    rows = users.map do |user|
      roles = user.account_users.map { |au| { account: au.account&.name, role: au.role } }
      admin = user.type == 'SuperAdmin' || roles.any? { |r| r[:role] == 'administrator' }
      { user: user, roles: roles, super_admin: user.type == 'SuperAdmin', admin: admin,
        mfa: user.otp_required_for_login? || false, last_sign_in_at: user.last_sign_in_at }
    end
    rows = rows.reject { |r| r[:mfa] } if only_missing
    rows.sort_by { |r| [r[:admin] && !r[:mfa] ? 0 : 1, r[:user].email.to_s] }
  end

  # --- System health (Tolzar::ControlCenter::Health) -------------------------------------------------------

  def health
    Tolzar::ControlCenter::Health.new(now: @now).view
  end

  def backup_status
    Tolzar::ControlCenter::Health.new(now: @now).backup_status
  end

  def mirror_lag
    Tolzar::ControlCenter::Health.new(now: @now).mirror_lag
  end

  private

  def workspace_rows(accounts)
    ids = accounts.map(&:id)
    counts = { users: AccountUser.where(account_id: ids).group(:account_id).count,
               inboxes: Inbox.where(account_id: ids).group(:account_id).count,
               conversations_30d: Conversation.unscoped.where(account_id: ids, created_at: (@now - 30.days)..).group(:account_id).count }
    subs = Tolzar::Subscription.where(account_id: ids).index_by(&:account_id)
    accounts.map do |account|
      sub = subs[account.id]
      { account: account, plan: sub&.plan, state: sub&.state(@now) || 'none',
        fair_use: (account.internal_attributes || {})[Tolzar::FairUse::KEY] }
        .merge(counts.transform_values { |by_account| by_account[account.id].to_i })
    end
  end

  # [account, subscription] for workspaces that have a billing row (read-only: never creates one).
  def subscriptions
    @subscriptions ||= begin
      subs = Tolzar::Subscription.all.index_by(&:account_id)
      Account.where(id: subs.keys).to_a.map { |account| [account, subs[account.id]] }
    end
  end

  def trials_ending(rows)
    rows.select { |_a, sub| sub.plan == 'trial' && sub.trial_ends_at&.between?(@now, @now + 7.days) }
        .map { |account, sub| { id: account.id, name: account.name, ends_at: sub.trial_ends_at } }
        .sort_by { |r| r[:ends_at] }
  end

  def fair_use(rows)
    rows.filter_map do |account, _sub|
      state = (account.internal_attributes || {})[Tolzar::FairUse::KEY]
      next unless state.is_a?(Hash) && state['allowance'].to_i.positive?

      { id: account.id, name: account.name, used: state['used'].to_i, allowance: state['allowance'].to_i,
        level: state['level'], month: state['month'] }
    end.sort_by { |r| -r[:used].fdiv(r[:allowance]) }.first(10)
  end
end
