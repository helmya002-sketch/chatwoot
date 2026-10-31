# Tolzar weekly staff report (round 4, c98), for the workspaces in TOLZAR_WEEKLY_REPORT_ACCOUNTS: one internal e-mail on
# Mondays to the workspace's administrators, never to a customer. The last 7 days per person (Tolzar::TeamLeaderboard)
# and per inbox (Tolzar::ChannelBreakdown), from the workspace's own records; nothing is estimated.
class Tolzar::WeeklyReport
  def self.accounts
    ENV.fetch('TOLZAR_WEEKLY_REPORT_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def self.recipients(account)
    account.administrators.pluck(:email).compact_blank
  end

  def initialize(account, now: Time.current)
    @account = account
    @now = now
  end

  def report
    people = Tolzar::TeamLeaderboard.new(@account, days: 7, now: @now).report[:people]
    inboxes = Tolzar::ChannelBreakdown.new(@account, days: 7, now: @now).report[:inboxes]
    { 'workspace' => @account.name, 'from' => (@now - 7.days).to_date.iso8601, 'to' => @now.to_date.iso8601,
      'people' => people.map { |row| line(row, :name, :replies, :resolved) },
      'inboxes' => inboxes.map { |row| line(row, :name, :conversations, :incoming) } }
  end

  private

  def line(row, *keys)
    row.slice(*keys).merge(first_reply: minutes(row[:first_reply])).stringify_keys
  end

  def minutes(seconds)
    return '—' if seconds.nil?

    seconds < 60 ? "#{seconds} s" : "#{(seconds / 60.0).round} min"
  end
end
