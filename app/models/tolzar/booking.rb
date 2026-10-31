# Tolzar native booking (plan §5), for TOLZAR_BOOKINGS_ACCOUNTS workspaces. data = { guests: [{name, contact_id}],
# lines: [...the document line shape, with date / until / time...], payments: [{amount, date, method, reference}],
# notes }. Totals and the payment state come from Tolzar::DocumentSpec; ID or passport numbers are refused. Statuses
# draft -> confirmed -> completed, or cancelled; every change is in history. Tolzar records payments, never charges.
class Tolzar::Booking < ApplicationRecord
  self.table_name = 'tolzar_bookings'

  STATUSES = %w[draft confirmed completed cancelled].freeze
  MOVES = { 'draft' => %w[confirmed cancelled], 'confirmed' => %w[completed cancelled], 'completed' => [], 'cancelled' => [] }.freeze

  Refused = Class.new(StandardError)

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :data_is_valid
  before_save :derive_dates

  scope :between, ->(from, to) { where('starts_on <= ? AND COALESCE(ends_on, starts_on) >= ?', to, from) }

  def self.enabled?(account_id)
    ENV.fetch('TOLZAR_BOOKINGS_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def checker
    Tolzar::DocumentSpec.new(data).check
  end

  def move!(to, by:)
    raise Refused, "a #{status} booking cannot become #{to}" unless MOVES.fetch(status, []).include?(to.to_s)
    raise Refused, 'fill in the placeholders before confirming' if to.to_s == 'confirmed' && checker.placeholders.any?

    self.status = to.to_s
    note("status:#{to}", by)
    save!
  end

  def record_payment!(amount:, by:, date: Date.current, method: nil, reference: nil)
    raise Refused, 'a cancelled booking takes no payments' if status == 'cancelled'
    raise Refused, 'a payment needs an amount' if BigDecimal(amount.to_s, exception: false).to_f.zero?

    self.data = data.merge('payments' => Array(data['payments']) + [{ 'amount' => amount.to_s, 'date' => date.to_s,
                                                                       'method' => method.to_s.first(40).presence,
                                                                       'reference' => reference.to_s.first(80).presence }.compact])
    note('payment', by)
    save!
  end

  # A draft booking document (voucher / confirmation) from this booking (Tolzar::Document).
  def to_document!(doc_type:, by:)
    Tolzar::Document.create!(account: account, conversation: conversation, contact: contact, doc_type: doc_type,
                             currency: currency, created_by_id: by&.id,
                             spec: data.slice('guests', 'lines', 'payments', 'notes').merge('booking_id' => id),
                             history: [{ 'action' => 'created', 'from_booking' => id, 'by' => by&.id, 'at' => Time.current.utc.iso8601,
                                         'version' => 1 }])
  end

  def view
    check = checker
    { id: id, status: status, currency: currency, starts_on: starts_on, ends_on: ends_on, total_cents: total_cents,
      paid_cents: paid_cents, balance_cents: [total_cents - paid_cents, 0].max, payment_state: check.payment_state,
      contact_id: contact_id, contact_name: contact&.name, conversation_id: conversation&.display_id, data: data,
      placeholders: check.placeholders, history: history.last(50), created_at: created_at }
  end

  private

  def data_is_valid
    check = Tolzar::DocumentSpec.new(data)
    check.check
    self.total_cents = check.total_cents
    self.paid_cents = check.paid_cents
    blocking = status == 'draft' ? check.errors.grep(/ID and passport/) : check.errors
    blocking.each { |e| errors.add(:data, e) }
  end

  # The booking's span from its lines' dates (date, and until for a range).
  def derive_dates
    days = Array(data['lines']).flat_map { |l| [l['date'], l['until']] if l.is_a?(Hash) }.compact.filter_map do |d|
      Date.iso8601(d.to_s)
    rescue ArgumentError
      nil
    end
    self.starts_on = days.min
    self.ends_on = days.max
  end

  def note(action, by)
    self.history = Array(history) + [{ 'action' => action, 'by' => by&.id, 'at' => Time.current.utc.iso8601 }]
  end
end
