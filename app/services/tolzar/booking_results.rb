# Tolzar Results → Bookings card: what documents and bookings brought in over a period, from the workspace's own
# records (no brain call). Money is per currency, never added across currencies. A part whose switch is off
# (TOLZAR_BOOKING_DOCS_ACCOUNTS / TOLZAR_BOOKINGS_ACCOUNTS) is nil.
#   documents: issued in the period (cancelled ones counted apart), per type, and per currency total / paid
#   bookings:  created in the period, per status, and per currency total / paid / due for confirmed + completed
class Tolzar::BookingResults
  DAYS = [7, 30, 90].freeze

  def initialize(account, days: 30, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
  end

  attr_reader :days

  def report
    { days: @days,
      documents: Tolzar::Document.enabled?(@account.id) ? documents : nil,
      bookings: Tolzar::Booking.enabled?(@account.id) ? bookings : nil }
  end

  private

  def documents
    scope = Tolzar::Document.where(account_id: @account.id, issued_at: @from..)
    live = scope.where(status: 'issued')
    { issued: live.count, cancelled: scope.where(status: 'void').count, by_type: live.group(:doc_type).count,
      money: money(live) }
  end

  def bookings
    scope = Tolzar::Booking.where(account_id: @account.id, created_at: @from..)
    { by_status: scope.group(:status).count, money: money(scope.where(status: %w[confirmed completed])) }
  end

  def money(scope)
    scope.group(:currency).pluck(:currency, Arel.sql('SUM(total_cents)'), Arel.sql('SUM(paid_cents)')).map do |currency, total, paid|
      { currency: currency, total_cents: total.to_i, paid_cents: paid.to_i, due_cents: [total.to_i - paid.to_i, 0].max }
    end.sort_by { |row| -row[:total_cents] }
  end
end
