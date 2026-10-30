# Tolzar Dashboard: open, unassigned and waiting conversations for every team of the workspace, in one
# request (the dashboard asked conversations/meta once per team). Three grouped counts over the same
# conversations the member may see (Conversations::PermissionFilterService, as conversations/meta does).
# "No team" is what is left of the totals, so conversations of a deleted team still add up.
class Tolzar::TeamSummary
  COUNTS = %i[open unassigned waiting].freeze

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def perform
    counts = {
      open: open_conversations.group(:team_id).count,
      unassigned: open_conversations.unassigned.group(:team_id).count,
      waiting: open_conversations.where.not(waiting_since: nil).group(:team_id).count
    }
    totals = counts.transform_values { |by_team| by_team.values.sum }
    teams = @account.teams.order(:name).map do |team|
      { id: team.id, name: team.name }.merge(counts.transform_values { |by_team| by_team[team.id] || 0 })
    end
    no_team = COUNTS.index_with { |key| totals[key] - teams.sum { |team| team[key] } }
    { totals: totals, teams: teams, no_team: no_team }
  end

  private

  def open_conversations
    @open_conversations ||= Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform.open
  end
end
