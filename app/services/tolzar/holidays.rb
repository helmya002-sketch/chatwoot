# Tolzar holiday calendar (round 4, c103): the days a workspace is closed (account.settings 'tolzar_holidays',
# [{ 'date' => 'YYYY-MM-DD', 'name' => '...' }]). On such a day, every inbox with working hours on counts as out of
# office all day, in the inbox's own time zone, so the away message and working-hours rules follow it.
# TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces only; off = upstream behaviour unchanged.
module Tolzar::Holidays
  MAX = 100
  NAME_MAX = 60

  module_function

  def list(account)
    Array((account.settings || {})['tolzar_holidays']).select { |h| h.is_a?(Hash) && valid_date?(h['date']) }
  end

  def closed_today?(inbox)
    return false unless Tolzar::CannedStarters.enabled?(inbox.account_id)

    today = Time.current.in_time_zone(inbox.timezone.presence || 'UTC').to_date.iso8601
    list(inbox.account).any? { |h| h['date'] == today }
  end

  # Cleans and saves the list: valid unique dates, sorted, names trimmed; returns the saved list.
  def save!(account, rows)
    clean = Array(rows).filter_map do |row|
      row = row.to_h.stringify_keys
      { 'date' => row['date'].to_s, 'name' => row['name'].to_s.strip.first(NAME_MAX) } if valid_date?(row['date'])
    end
    clean = clean.uniq { |h| h['date'] }.sort_by { |h| h['date'] }.first(MAX)
    account.update!(settings: (account.settings || {}).merge('tolzar_holidays' => clean))
    clean
  end

  def valid_date?(value)
    value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value.to_s).present?
  rescue ArgumentError
    false
  end
end
