# Tolzar booking documents and bookings: privacy (plan §1). Documents and bookings stay in the workspace's own
# database; this is what DSAR export, contact erase and the retention period do with them.
#   export(contact)              the person's documents and bookings, as the API shows them
#   erase!(contact)              drafts are deleted; issued and cancelled documents keep their number and totals (the
#                                register stays gapless) but lose every name, note and link to the person; bookings
#                                are anonymised the same way
#   forget_conversations!(ids)   the retention period: the same, for the documents and bookings of conversations
#                                that were deleted (ids are conversation ids, not display ids)
# Every query is scoped to the account.
class Tolzar::DocumentPrivacy
  ERASED = 'Erased on request'

  def initialize(account)
    @account = account
  end

  def export(contact)
    { documents: documents.where(contact_id: contact.id).order(:created_at).map(&:view),
      bookings: bookings.where(contact_id: contact.id).order(:created_at).map(&:view) }
  end

  def erase!(contact)
    forget!(documents.where(contact_id: contact.id), bookings.where(contact_id: contact.id), 'erased')
  end

  def forget_conversations!(conversation_ids)
    return { documents: 0, bookings: 0 } if conversation_ids.blank?

    forget!(documents.where(conversation_id: conversation_ids), bookings.where(conversation_id: conversation_ids), 'retention')
  end

  private

  def documents
    Tolzar::Document.where(account_id: @account.id)
  end

  def bookings
    Tolzar::Booking.where(account_id: @account.id)
  end

  # update_columns on purpose: a person never edits an issued document, but erasure must still reach it.
  def forget!(doc_scope, booking_scope, why)
    at = Time.current.utc.iso8601
    drafts = doc_scope.where(status: 'draft').delete_all
    kept = 0
    doc_scope.where.not(status: 'draft').find_each do |d|
      d.update_columns(spec: scrub(d.spec), contact_id: nil, conversation_id: nil, updated_at: Time.current,
                       history: Array(d.history) + [{ 'action' => why, 'at' => at, 'version' => d.version }])
      kept += 1
    end
    booked = 0
    booking_scope.find_each do |b|
      b.update_columns(data: scrub(b.data), contact_id: nil, conversation_id: nil, updated_at: Time.current,
                       history: Array(b.history) + [{ 'action' => why, 'at' => at }])
      booked += 1
    end
    { documents: drafts + kept, bookings: booked }
  end

  # Names, notes, titles, free-text descriptions and payment references go; line types, quantities, prices and dates
  # stay for the register.
  def scrub(spec)
    spec = (spec || {}).deep_dup
    spec['guests'] = [] if spec.key?('guests')
    spec['lines'] = Array(spec['lines']).map { |l| l.is_a?(Hash) ? l.merge('description' => l['type'].to_s.tr('_', ' ')) : l } if spec.key?('lines')
    spec['notes'] = ERASED if spec['notes'].present?
    spec.delete('title')
    spec['payments'] = Array(spec['payments']).map { |p| p.is_a?(Hash) ? p.except('reference') : p } if spec.key?('payments')
    spec
  end
end
