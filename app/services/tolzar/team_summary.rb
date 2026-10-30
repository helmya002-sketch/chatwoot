# Tolzar Dashboard: open, unassigned and waiting conversations for every team of the workspace, in one
# request (the dashboard asked conversations/meta once per team). Three grouped counts over the same
# conversations the member may see (Conversations::PermissionFilterService, as conversations/meta does).
# "No team" is what is left of the totals, so conversations of a deleted team still add up.
#
# Waiting follows the workspace's SLA (the brain's first-reply SLA, Settings > SLA) when it is on: the
# brain starts the clock at the first customer message since the last reply, which is Chatwoot's
# `waiting_since`, so waiting = open with `waiting_since` set (the reply is due at waiting_since + the
# SLA minutes, counted in working hours if the SLA says so; running or past due both count). With no SLA
# on: waiting = open with no agent reply yet (`first_reply_created_at` empty). `waiting_rule` names it.
class Tolzar::TeamSummary
  COUNTS = %i[open unassigned waiting].freeze
  # The brain's default when the SLA has no minutes saved (brain app.py POST /sla).
  DEFAULT_SLA_MINUTES = 15

  # sla: the brain's SLA config ({enabled, first_reply_minutes, working_hours_only}) or nil.
  def initialize(account:, user:, sla: nil)
    @account = account
    @user = user
    @sla = sla if sla.is_a?(Hash) && sla['enabled'] == true
  end

  def perform
    counts = {
      open: open_conversations.group(:team_id).count,
      unassigned: open_conversations.unassigned.group(:team_id).count,
      waiting: waiting_conversations.group(:team_id).count
    }
    totals = counts.transform_values { |by_team| by_team.values.sum }
    teams = @account.teams.order(:name).map do |team|
      { id: team.id, name: team.name }.merge(counts.transform_values { |by_team| by_team[team.id] || 0 })
    end
    no_team = COUNTS.index_with { |key| totals[key] - teams.sum { |team| team[key] } }
    { waiting_rule: waiting_rule, totals: totals, teams: teams, no_team: no_team }
  end

  private

  def open_conversations
    @open_conversations ||= Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform.open
  end

  def waiting_conversations
    return open_conversations.where(first_reply_created_at: nil) unless @sla

    open_conversations.where.not(waiting_since: nil)
  end

  # "sla:reply_within_30m_working_hours", "sla:reply_within_30m" or "first_reply_pending".
  def waiting_rule
    return 'first_reply_pending' unless @sla

    minutes = (@sla['first_reply_minutes'].presence || DEFAULT_SLA_MINUTES).to_i
    "sla:reply_within_#{minutes}m#{'_working_hours' if @sla.fetch('working_hours_only', true)}"
  end
end
