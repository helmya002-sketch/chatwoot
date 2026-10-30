# Tolzar fair use per plan (queue item I, Oracle decision L-34e; switch TOLZAR_FAIR_USE, default off).
# Each trial or paid plan includes a monthly allowance of AI replies (TOLZAR_FAIR_USE_ALLOWANCES as
# "plan:replies,…"; the default is the published BUSINESS-MODEL figures). It is a SOFT limit: nothing is ever
# refused, stopped or charged. At 80% ("near") and 100% ("over") of the allowance, once a month each, the
# workspace's Owner gets an in-app notice (the account's internal_attributes['tolzar_fair_use'], shown by
# FairUseBanner) and an e-mail, and Tolzar gets an alert (a log line and TOLZAR_FAIR_USE_ALERT_TO). The brain
# counts the replies (GET /fair_use: model-written replies SENT live; Business counts its pool); its hard caps
# (per conversation, per day, burst) stay as abuse protection only.
class Tolzar::FairUse
  DEFAULT_ALLOWANCES = 'trial:6000,starter:1500,team:6000,business:18000'.freeze
  NEAR = 0.8
  KEY = 'tolzar_fair_use'.freeze
  RANK = { 'near' => 1, 'over' => 2 }.freeze

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('TOLZAR_FAIR_USE', false))
  end

  # { 'starter' => 1500, … }: plans without an entry (internal) have no allowance.
  def self.allowances
    ENV.fetch('TOLZAR_FAIR_USE_ALLOWANCES', DEFAULT_ALLOWANCES).to_s.split(',').filter_map do |pair|
      plan, count = pair.split(':', 2).map { |v| v.to_s.strip }
      [plan, count.to_i] if Tolzar::Subscription::PLANS.include?(plan) && count.to_i.positive?
    end.to_h
  end

  def self.level(used, allowance)
    return nil unless allowance.to_i.positive?
    return 'over' if used >= allowance

    'near' if used >= (allowance * NEAR).ceil
  end

  def initialize(subscription, brain: Tolzar::BrainClient)
    @subscription = subscription
    @account = subscription.account
    @brain = brain
  end

  # Reads the brain's count, stores the state for the in-app notice, and notifies once per level per month.
  # Returns the stored state, or nil when the plan has no allowance or the brain gave no count.
  def check!
    allowance = self.class.allowances[@subscription.plan]
    return unless allowance

    status = @brain.get("/fair_use?account_id=#{@account.id}", account_id: @account.id)
    return unless status.is_a?(Hash) && status['used'].is_a?(Integer) && status['month'].present?

    state = next_state(status['used'], status['month'].to_s, allowance)
    @account.update!(internal_attributes: (@account.internal_attributes || {}).merge(KEY => state))
    notify(state) if state.delete('notify_now')
    state
  end

  private

  def next_state(used, month, allowance)
    level = self.class.level(used, allowance)
    before = (@account.internal_attributes || {})[KEY] || {}
    notified = before['month'] == month ? before['notified'] : nil
    notify_now = level.present? && RANK[level] > RANK[notified].to_i
    { 'month' => month, 'used' => used, 'allowance' => allowance, 'plan' => @subscription.plan, 'level' => level,
      'notified' => notify_now ? level : notified, 'checked_at' => Time.current.utc.iso8601, 'notify_now' => notify_now }
  end

  def notify(state)
    Rails.logger.warn("[Tolzar] fair use #{state['level']} account=#{@account.id} plan=#{state['plan']} " \
                      "used=#{state['used']}/#{state['allowance']} month=#{state['month']}")
    meta = state.slice('level', 'used', 'allowance', 'month', 'plan').merge('workspace' => @account.name, 'account_id' => @account.id)
    owner = User.find_by(id: Tolzar::AccountOwner.user_id(@account))
    Tolzar::FairUseMailer.with(account: @account).notice(owner.email, meta).deliver_later if owner&.email.present?
    alert_to = ENV.fetch('TOLZAR_FAIR_USE_ALERT_TO', '').presence
    Tolzar::FairUseMailer.with(account: @account).alert(alert_to, meta).deliver_later if alert_to
  end
end
