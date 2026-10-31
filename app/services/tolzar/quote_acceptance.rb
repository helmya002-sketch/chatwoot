# Tolzar quote acceptance link (round 4, D2): a public link per issued quote where the customer reads the quote
# (number, lines, total, valid until) and presses Accept. For Tolzar::Document workspaces that are also in
# TOLZAR_QUOTE_ACCEPT_ACCOUNTS; any workspace member gets the link and passes it on themselves.
# - The link carries HMAC-SHA256(secret_key_base, "tolzar-quote:<account>:<doc>:<nonce>"); the nonce lives in
#   account.settings['tolzar_quote_links'][doc_id]['nonce'].
# - accept! records accepted_at there and makes one DRAFT confirmation copying the quote's spec; a second Accept
#   returns the same draft. Nothing is issued or sent to anyone: staff take it from there.
class Tolzar::QuoteAcceptance
  SETTINGS_KEY = 'tolzar_quote_links'.freeze

  Refused = Class.new(StandardError)

  def self.enabled?(account_id)
    Tolzar::Document.enabled?(account_id) &&
      ENV.fetch('TOLZAR_QUOTE_ACCEPT_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
         .include?(account_id.to_i)
  end

  def self.links(account)
    (account.settings || {})[SETTINGS_KEY] || {}
  end

  def self.state(document)
    links(document.account)[document.id.to_s] || {}
  end

  def self.write_state(account, document, values)
    all = links(account).merge(document.id.to_s => state(document).merge(values))
    account.update!(settings: (account.settings || {}).merge(SETTINGS_KEY => all))
  end

  def self.token(document)
    write_state(document.account, document, 'nonce' => SecureRandom.hex(16)) if state(document)['nonce'].to_s.empty?
    payload = "tolzar-quote:#{document.account_id}:#{document.id}:#{state(document)['nonce']}"
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, payload)
  end

  def self.url(document)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/tz/quote/#{document.id}/#{token(document)}"
  end

  # The document, when the switch is on and the token matches its link; nil otherwise (the caller answers 404).
  def self.verify(document_id, given)
    return unless given.to_s.length == 64

    document = Tolzar::Document.find_by(id: document_id)
    return unless document && enabled?(document.account_id) && state(document)['nonce'].present?
    return unless ActiveSupport::SecurityUtils.secure_compare(token(document), given.to_s)

    document
  end

  def self.valid_until(document)
    Date.iso8601(document.spec['valid_until'].to_s)
  rescue ArgumentError
    nil
  end

  # An issued quote, not void and not past its valid-until date (no date = open).
  def self.open?(document, today: Date.current)
    return false unless document.doc_type == 'quote' && document.status == 'issued'

    until_date = valid_until(document)
    until_date.nil? || until_date >= today
  end

  def self.accepted?(document)
    state(document)['accepted_at'].present?
  end

  # The draft confirmation. Idempotent: a second call returns the first draft.
  def self.accept!(document, now: Time.current)
    account = document.account
    account.with_lock do
      done = state(document)
      found = Tolzar::Document.find_by(account_id: account.id, id: done['confirmation_id']) if done['accepted_at'].present?
      found || first_accept(account, document, now)
    end
  end

  def self.first_accept(account, document, now)
    raise Refused, 'no longer valid' unless open?(document, today: now.to_date)

    confirmation = create_confirmation(document, now)
    write_state(account, document, 'accepted_at' => now.utc.iso8601, 'confirmation_id' => confirmation.id)
    confirmation
  end

  def self.create_confirmation(document, now)
    Tolzar::Document.create!(
      account: document.account, conversation: document.conversation, contact: document.contact,
      doc_type: 'confirmation', currency: document.currency, language: document.language,
      spec: document.spec.deep_dup,
      history: [{ 'action' => 'created', 'by' => nil, 'at' => now.utc.iso8601, 'version' => 1,
                  'from_quote' => document.id, 'note' => 'customer accepted the quote link' }]
    )
  end
  private_class_method :first_accept, :create_confirmation, :write_state
end
