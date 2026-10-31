# Tolzar booking documents: the document's content (spec) and its checks, generic for any business.
#   spec = { title, guests: [{name}], lines: [{type, description, qty, unit_price, date, time, nights, guests,
#            valid_until}], payments: [{amount, date, method, reference}], stated_total, open_date, valid_until,
#            notes, terms }
# Rules (plan §1): totals are computed (qty × unit price); a stated total that disagrees stops the document; a
# discount is a staff-entered line of type "discount" (negative), never added by the AI; any placeholder
# ("TBC", "{{…}}", "??") blocks issuing; there are no fields for ID or passport numbers, and a value that looks
# like one is refused.
class Tolzar::DocumentSpec
  TYPES = %w[voucher quote confirmation payment_summary].freeze
  LINE_TYPES = %w[course appointment room_night order_item service rental extra discount].freeze
  PLACEHOLDER = /(\bTBC\b|\{\{.*?\}\}|\?\?)/i
  ID_KEY = /(passport|national_?id|id_?number|identity|ssn|tax_?id)/i
  # An ID number written out ("passport no. A1234567"), not a mention ("bring your passport").
  ID_VALUE = /\b(passport|national id|id)\s*(no\.?|number|nr\.?|#)?\s*[:#-]?\s*[A-Z]{0,3}\d{5,}/i
  MAX_LINES = 60
  MAX_GUESTS = 40

  attr_reader :spec, :errors, :placeholders

  def initialize(spec)
    @spec = (spec || {}).deep_stringify_keys
    @errors = []
    @placeholders = []
  end

  def check
    @errors = []
    @placeholders = []
    check_shape
    check_ids(@spec, [])
    find_placeholders(@spec, [])
    check_total
    self
  end

  def valid?
    check.errors.empty?
  end

  # Ready to issue: valid and no placeholder left.
  def issuable?
    valid? && @placeholders.empty?
  end

  def lines
    Array(@spec['lines']).select { |l| l.is_a?(Hash) }
  end

  def total_cents
    lines.sum { |l| line_cents(l) }
  end

  def paid_cents
    Array(@spec['payments']).select { |p| p.is_a?(Hash) }.sum { |p| cents(p['amount']) }
  end

  # paid / deposit / due, from the payments against the total.
  def payment_state
    paid = paid_cents
    return 'due' if paid <= 0
    return 'paid' if paid >= total_cents

    'deposit'
  end

  def line_cents(line)
    qty = line['qty'].presence || 1
    (BigDecimal(qty.to_s) * cents(line['unit_price'])).round.to_i
  rescue ArgumentError
    0
  end

  private

  def cents(value)
    (BigDecimal(value.to_s.presence || '0') * 100).round.to_i
  rescue ArgumentError
    0
  end

  def check_shape
    @errors << 'lines: at least one line' if lines.empty?
    @errors << "lines: at most #{MAX_LINES}" if lines.size > MAX_LINES
    @errors << "guests: at most #{MAX_GUESTS}" if Array(@spec['guests']).size > MAX_GUESTS
    lines.each_with_index do |line, i|
      @errors << "lines[#{i}]: unknown type #{line['type']}" unless LINE_TYPES.include?(line['type'].to_s)
      @errors << "lines[#{i}]: a description" if line['description'].to_s.strip.empty?
      @errors << "lines[#{i}]: a resource of at most 60 characters" if line['resource'].to_s.length > 60
      check_number(line['qty'], "lines[#{i}].qty", positive: true) if line['qty'].present?
      check_number(line['unit_price'], "lines[#{i}].unit_price") unless placeholder?(line['unit_price'])
      if line['type'] == 'discount' && line_cents(line).positive?
        @errors << "lines[#{i}]: a discount is a negative amount"
      elsif line['type'] != 'discount' && line_cents(line).negative?
        @errors << "lines[#{i}]: only a discount line can be negative"
      end
    end
  end

  def check_number(value, path, positive: false)
    number = BigDecimal(value.to_s)
    @errors << "#{path}: must be more than 0" if positive && number <= 0
  rescue ArgumentError
    @errors << "#{path}: not a number"
  end

  def check_total
    stated = @spec['stated_total']
    return if stated.blank? || placeholder?(stated)
    return if cents(stated) == total_cents

    @errors << "stated_total: #{stated} does not match the lines (#{format('%.2f', total_cents / 100.0)})"
  end

  def check_ids(node, path)
    case node
    when Hash
      node.each do |k, v|
        @errors << "#{(path + [k]).join('.')}: ID and passport numbers are never stored in documents" if k.to_s.match?(ID_KEY)
        check_ids(v, path + [k])
      end
    when Array then node.each_with_index { |v, i| check_ids(v, path + [i]) }
    when String
      @errors << "#{path.join('.')}: ID and passport numbers are never stored in documents" if node.match?(ID_VALUE)
    end
  end

  def find_placeholders(node, path)
    case node
    when Hash then node.each { |k, v| find_placeholders(v, path + [k]) }
    when Array then node.each_with_index { |v, i| find_placeholders(v, path + [i]) }
    when String then @placeholders << path.join('.') if placeholder?(node)
    end
  end

  def placeholder?(value)
    value.is_a?(String) && value.match?(PLACEHOLDER)
  end
end
