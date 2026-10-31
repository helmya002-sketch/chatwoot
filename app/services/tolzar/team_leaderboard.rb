# Tolzar Results → Team (round 4, c96): per person over 7 / 30 / 90 days, from the workspace's own records.
#   replies:      public replies they sent (outgoing, not private notes)
#   first_reply:  median first-reply time in seconds (reporting events "first_response")
#   resolved:     conversations they resolved (reporting events "conversation_resolved")
#   csat:         average rating (1-5) and how many ratings, on conversations assigned to them
# Everyone in the workspace is listed, also with zeros, so nobody silently drops off the board.
class Tolzar::TeamLeaderboard
  DAYS = [7, 30, 90].freeze

  def initialize(account, days: 30, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
  end

  def report
    replies = replies_by_user
    first = first_reply_by_user
    resolved = events('conversation_resolved').group(:user_id).count
    csat = csat_by_user
    people = @account.users.order(:name).map do |user|
      { id: user.id, name: user.available_name, replies: replies[user.id].to_i, first_reply: first[user.id]&.round,
        resolved: resolved[user.id].to_i, csat: csat[user.id] }
    end
    { days: @days, people: people.sort_by { |row| [-row[:replies], -row[:resolved], row[:name].to_s] } }
  end

  private

  def replies_by_user
    @account.messages.where(message_type: :outgoing, private: false, sender_type: 'User', created_at: @from..)
            .group(:sender_id).count
  end

  def first_reply_by_user
    events('first_response').where.not(user_id: nil).group(:user_id)
                            .pluck(:user_id, Arel.sql('PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY value)')).to_h
  end

  def csat_by_user
    CsatSurveyResponse.where(account_id: @account.id, created_at: @from..).where.not(assigned_agent_id: nil)
                      .group(:assigned_agent_id).pluck(:assigned_agent_id, Arel.sql('AVG(rating)'), Arel.sql('COUNT(*)'))
                      .to_h { |id, avg, n| [id, { average: avg.to_f.round(2), count: n.to_i }] }
  end

  def events(name)
    ReportingEvent.where(account_id: @account.id, name: name, created_at: @from..)
  end
end
