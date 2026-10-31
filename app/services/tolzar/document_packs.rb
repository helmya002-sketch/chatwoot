# Tolzar booking documents: industry packs (plan §1). Each line type has the fields the editor shows and the AI
# drafting fills; each document type has default terms ("Good to know"). Generic for any business: a workspace
# edits its own terms (Tolzar::DocumentBranding) and these are only the starting point.
module Tolzar::DocumentPacks
  LINE_FIELDS = {
    'course' => %w[date time duration guests],
    'appointment' => %w[date time duration],
    'room_night' => %w[date until nights guests],
    'order_item' => %w[qty size],
    'service' => %w[date qty],
    'rental' => %w[date until qty size],
    'extra' => %w[qty],
    'discount' => []
  }.freeze

  DEFAULT_TERMS = {
    'voucher' => 'Show this voucher (on your phone or printed) when you arrive. It is valid until the date shown; ' \
                 'to change the date, reply in this conversation.',
    'quote' => 'Prices are valid until the date shown. Nothing is booked until you confirm and the booking is ' \
               'confirmed in writing.',
    'confirmation' => 'Your booking is confirmed for the dates shown. To change or cancel, reply in this conversation.',
    'payment_summary' => 'A summary of what you paid and what is still due. This is not a tax invoice.'
  }.freeze

  def self.line_types
    Tolzar::DocumentSpec::LINE_TYPES.index_with { |type| LINE_FIELDS.fetch(type, []) }
  end

  def self.default_terms(doc_type)
    DEFAULT_TERMS.fetch(doc_type.to_s, '')
  end
end
