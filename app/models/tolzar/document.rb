# Tolzar booking document (TOLZAR-BOOKING-DOCUMENTS-PLAN-2026-10-31.md). Drafts are edited freely (each save a new
# version in history); issue! checks the spec (Tolzar::DocumentSpec: totals, no placeholder, no ID numbers) and
# gives the gapless number PREFIX-YY-NNNN; void! keeps the number. An issued document is never edited: a change is
# a new draft. Every step is in history (who, when, what). Only for TOLZAR_BOOKING_DOCS_ACCOUNTS workspaces.
class Tolzar::Document < ApplicationRecord
  self.table_name = 'tolzar_documents'

  STATUSES = %w[draft issued void].freeze
  DEFAULT_PREFIXES = { 'voucher' => 'VCH', 'quote' => 'QTE', 'confirmation' => 'BKG', 'payment_summary' => 'PAY' }.freeze
  PREFIX = /\A[A-Z0-9]{2,8}\z/

  Refused = Class.new(StandardError)

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  validates :doc_type, inclusion: { in: Tolzar::DocumentSpec::TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :spec_is_valid

  scope :register, -> { order(created_at: :desc) }

  def self.enabled?(account_id)
    ENV.fetch('TOLZAR_BOOKING_DOCS_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def self.prefix_for(account, doc_type)
    custom = ((account.settings || {})['tolzar_document_prefixes'] || {})[doc_type].to_s.upcase
    custom.match?(PREFIX) ? custom : DEFAULT_PREFIXES.fetch(doc_type)
  end

  def checker
    Tolzar::DocumentSpec.new(spec).check
  end

  def draft?
    status == 'draft'
  end

  # A draft's new content, as a new version.
  def revise!(new_spec, by:)
    raise Refused, 'only a draft can be edited' unless draft?

    self.spec = new_spec
    self.version += 1
    note('edited', by)
    save!
  end

  def issue!(by:, now: Time.current)
    raise Refused, 'only a draft can be issued' unless draft?

    check = checker
    raise Refused, check.errors.first if check.errors.any?
    raise Refused, "fill in the placeholders first: #{check.placeholders.first(5).join(', ')}" if check.placeholders.any?

    transaction do
      year = now.year % 100
      counter = Tolzar::DocumentCounter.lock.find_or_create_by!(account_id: account_id, doc_type: doc_type, year: year)
      counter.update!(last_seq: counter.last_seq + 1)
      assign_attributes(status: 'issued', year: year, seq: counter.last_seq, issued_at: now, issued_by_id: by&.id,
                        number: format('%<p>s-%<y>02d-%<n>04d', p: self.class.prefix_for(account, doc_type), y: year, n: counter.last_seq))
      note('issued', by)
      save!
    end
  end

  def void!(reason:, by:, now: Time.current)
    raise Refused, 'only an issued document can be voided' unless status == 'issued'
    raise Refused, 'a reason is needed' if reason.to_s.strip.empty?

    assign_attributes(status: 'void', voided_at: now, void_reason: reason.to_s.strip.first(300))
    note('voided', by)
    save!
  end

  def view
    check = checker
    { id: id, doc_type: doc_type, status: status, number: number, currency: currency, total_cents: total_cents,
      paid_cents: paid_cents, payment_state: check.payment_state, language: language, spec: spec, version: version,
      conversation_id: conversation&.display_id, contact_id: contact_id, contact_name: contact&.name,
      issued_at: issued_at, voided_at: voided_at, void_reason: void_reason, created_at: created_at,
      errors: check.errors, placeholders: check.placeholders, history: history.last(50) }
  end

  private

  def spec_is_valid
    check = Tolzar::DocumentSpec.new(spec)
    check.check
    self.total_cents = check.total_cents
    self.paid_cents = check.paid_cents
    # A draft may be incomplete except for ID numbers, which are never stored, not even in a draft.
    blocking = draft? ? check.errors.grep(/ID and passport/) : check.errors
    blocking.each { |e| errors.add(:spec, e) }
  end

  def note(action, by)
    self.history = Array(history) + [{ 'action' => action, 'by' => by&.id, 'at' => Time.current.utc.iso8601, 'version' => version }]
  end
end
