# Tolzar Results → Channels (round 4, c97): per inbox over 7 / 30 / 90 days, from the workspace's own records.
#   conversations: started in the period
#   incoming:      customer messages received
#   first_reply:   median first-reply time in seconds (reporting events "first_response")
#   resolved:      conversations resolved (reporting events "conversation_resolved")
# Every inbox is listed, also with zeros; the channel type lets the screen show its icon and name.
class Tolzar::ChannelBreakdown
  DAYS = [7, 30, 90].freeze

  def initialize(account, days: 30, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
  end

  def report
    started = @account.conversations.where(created_at: @from..).group(:inbox_id).count
    incoming = @account.messages.where(message_type: :incoming, created_at: @from..).group(:inbox_id).count
    first = events('first_response').group(:inbox_id)
                                    .pluck(:inbox_id, Arel.sql('PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY value)')).to_h
    resolved = events('conversation_resolved').group(:inbox_id).count
    inboxes = @account.inboxes.order(:name).map do |inbox|
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, conversations: started[inbox.id].to_i,
        incoming: incoming[inbox.id].to_i, first_reply: first[inbox.id]&.round, resolved: resolved[inbox.id].to_i }
    end
    { days: @days, inboxes: inboxes.sort_by { |row| [-row[:conversations], row[:name].to_s] } }
  end

  private

  def events(name)
    ReportingEvent.where(account_id: @account.id, name: name, created_at: @from..)
  end
end
