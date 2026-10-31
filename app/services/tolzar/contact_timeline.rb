# Tolzar contact timeline (round 4, c99): one contact's conversations, documents, bookings and win/loss reason in one
# list, newest first, from the workspace's own records. Documents and bookings appear only while their switches are
# on (Tolzar::Document / Tolzar::Booking.enabled?). Drafts of documents are left out: only what was issued or voided.
# Conversations follow the viewer's access (Conversations::PermissionFilterService, as the contact's conversation list).
class Tolzar::ContactTimeline
  LIMIT = 100

  def initialize(account, contact, user)
    @account = account
    @contact = contact
    @user = user
  end

  def events
    rows = conversations + documents + bookings + outcome
    rows.sort_by { |row| row[:at].to_s }.reverse.first(LIMIT)
  end

  private

  def conversations
    scope = @account.conversations.where(contact_id: @contact.id).includes(:inbox)
    scope = Conversations::PermissionFilterService.new(scope, @user, @account).perform
    scope.reorder(created_at: :desc).limit(LIMIT).map do |c|
      { kind: 'conversation', at: c.created_at.iso8601, id: c.display_id, status: c.status, inbox: c.inbox&.name }
    end
  end

  def documents
    return [] unless Tolzar::Document.enabled?(@account.id)

    Tolzar::Document.where(account_id: @account.id, contact_id: @contact.id, status: %w[issued void])
                    .order(issued_at: :desc).limit(LIMIT).map do |d|
      { kind: 'document', at: (d.issued_at || d.created_at).iso8601, id: d.id, doc_type: d.doc_type, number: d.number,
        status: d.status, total_cents: d.total_cents, currency: d.currency }
    end
  end

  def bookings
    return [] unless Tolzar::Booking.enabled?(@account.id)

    Tolzar::Booking.where(account_id: @account.id, contact_id: @contact.id).order(created_at: :desc).limit(LIMIT).map do |b|
      { kind: 'booking', at: b.created_at.iso8601, id: b.id, status: b.status, starts_on: b.starts_on&.iso8601,
        total_cents: b.total_cents, currency: b.currency }
    end
  end

  def outcome
    attrs = @contact.custom_attributes || {}
    match = attrs['tolzar_outcome_reason'].to_s.match(Tolzar::OutcomeReasons::REASON)
    at = Time.zone.parse(attrs['tolzar_outcome_reason_at'].to_s)
    return [] unless match && at

    [{ kind: 'outcome', at: at.iso8601, outcome: match[1], reason: match[2] }]
  rescue ArgumentError
    []
  end
end
