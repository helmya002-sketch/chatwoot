# Tolzar Results → Reply-time target (round 4, G2): per inbox over 7 / 30 / 90 days, how many conversations got
# their first reply within the workspace's target and how many were late, from reporting events "first_response".
# The target is the brain's first-reply SLA (Settings > SLA) when it is on, counted in working hours when the SLA
# says so (value_in_business_hours); otherwise the default 15 minutes, reported as the default.
class Tolzar::ReplyTarget
  DAYS = [7, 30, 90].freeze
  DEFAULT_MINUTES = Tolzar::TeamSummary::DEFAULT_SLA_MINUTES

  # sla: the brain's SLA config ({enabled, first_reply_minutes, working_hours_only}) or nil.
  def initialize(account, days: 30, sla: nil, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
    @sla = sla if sla.is_a?(Hash) && sla['enabled'] == true
  end

  def report
    names = @account.inboxes.pluck(:id, :name).to_h
    counts = within_and_late
    inboxes = names.map do |id, name|
      within, late = counts.fetch(id, [0, 0])
      { id: id, name: name, within: within, late: late }
    end
    { days: @days, target: target, inboxes: inboxes.sort_by { |row| [-(row[:within] + row[:late]), row[:name].to_s] } }
  end

  private

  def target
    return { minutes: DEFAULT_MINUTES, source: 'default', working_hours: false } unless @sla

    { minutes: minutes, source: 'sla', working_hours: working_hours? }
  end

  def minutes
    (@sla['first_reply_minutes'].presence || DEFAULT_MINUTES).to_i
  end

  def working_hours?
    @sla.present? && @sla.fetch('working_hours_only', true) == true
  end

  # { inbox_id => [within, late] }; a missing business-hours value falls back to the plain value.
  def within_and_late
    column = working_hours? ? 'COALESCE(value_in_business_hours, value)' : 'value'
    limit = (@sla ? minutes : DEFAULT_MINUTES) * 60
    within = ActiveRecord::Base.sanitize_sql_array(["COUNT(*) FILTER (WHERE #{column} <= :limit)", { limit: limit }])
    late = ActiveRecord::Base.sanitize_sql_array(["COUNT(*) FILTER (WHERE #{column} > :limit)", { limit: limit }])
    ReportingEvent.where(account_id: @account.id, name: 'first_response', created_at: @from..).where.not(inbox_id: nil)
                  .group(:inbox_id).pluck(:inbox_id, Arel.sql(within), Arel.sql(late))
                  .to_h { |id, w, l| [id, [w.to_i, l.to_i]] }
  end
end
