# Tolzar win/loss reasons (round 4, c95): why deals were won or lost over 7 / 30 / 90 days, from the reasons the team
# picks on the Pipeline board (contact custom attributes tolzar_outcome_reason "won:price", tolzar_outcome_reason_at).
class Tolzar::OutcomeReasons
  DAYS = [7, 30, 90].freeze
  REASON = /\A(won|lost):([a-z_]{1,30})\z/

  def initialize(account, days: 30, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
  end

  def report
    rows = @account.contacts.where("custom_attributes ? 'tolzar_outcome_reason'")
                   .pluck(Arel.sql("custom_attributes->>'tolzar_outcome_reason'"), Arel.sql("custom_attributes->>'tolzar_outcome_reason_at'"))
    counts = Hash.new(0)
    rows.each do |reason, at|
      next unless reason.to_s.match?(REASON) && recent?(at)

      counts[reason] += 1
    end
    reasons = counts.map do |key, n|
      outcome, reason = key.split(':')
      { outcome: outcome, reason: reason, count: n }
    end
    { days: @days, reasons: reasons.sort_by { |row| [row[:outcome], -row[:count]] } }
  end

  private

  def recent?(at)
    Time.zone.parse(at.to_s)&.>=(@from)
  rescue ArgumentError
    false
  end
end
