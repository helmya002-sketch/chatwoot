# Tolzar booking connector: a Tolzar booking document (draft or issued) as a DRAFT booking for the external system
# (the DWT body: guests, lines with a catalog reference and day, currency, tolzar_conversation_id, notes). Lines
# without a catalog reference are not sent (the booking system prices from its own catalog); they are listed
# back so staff see what stayed out. Prices are never sent: the booking system prices and confirms.
class Tolzar::BookingConnectors::FromDocument
  Refused = Class.new(StandardError)

  def initialize(document)
    @document = document
    @spec = (document.spec || {}).deep_stringify_keys
  end

  # => [body, skipped_line_descriptions]
  def build
    raise Refused, 'fill in the placeholders first' if Tolzar::DocumentSpec.new(@spec).check.placeholders.any?

    lines, skipped = Array(@spec['lines']).select { |l| l.is_a?(Hash) }.partition { |l| l['catalog_ref'].present? }
    raise Refused, 'no line has a catalog reference to book' if lines.empty?

    body = { guests: guests, lines: lines.map { |l| line(l) }, currency: @document.currency,
             tolzar_conversation_id: @document.conversation&.display_id&.to_s, notes: @spec['notes'].to_s.first(2000).presence }.compact
    [body, skipped.map { |l| l['description'].to_s }]
  end

  private

  def guests
    list = Array(@spec['guests']).select { |g| g.is_a?(Hash) && g['name'].present? }.map { |g| { name: g['name'].to_s.first(120) } }
    contact = @document.contact
    if contact
      first = { name: contact.name, phone: contact.phone_number, email: contact.email, tolzar_contact_id: contact.id.to_s }.compact
      list = list.empty? ? [first] : [list.first.merge(first.except(:name))] + list.drop(1)
    end
    list
  end

  def line(spec_line)
    { course: spec_line['catalog_ref'].to_s.first(120), day: spec_line['date'].presence, checkin: spec_line['time'].presence,
      guests: spec_line['guests'].presence || 'all', qty: spec_line['qty'].presence }.compact
  end
end
