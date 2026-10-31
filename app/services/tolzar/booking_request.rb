# Tolzar public booking request (round 4, D1): a workspace's own link to a small public form (date, people, name,
# e-mail or phone, a short note). For TOLZAR_BOOKINGS_ACCOUNTS workspaces that are also in
# TOLZAR_BOOKING_REQUESTS_ACCOUNTS; administrators copy and reset the link.
# - The link carries HMAC-SHA256(secret_key_base, "tolzar-book:<account>:<nonce>"); the nonce lives in
#   account.settings['tolzar_booking_request_nonce']. Reset = a new nonce, and the old link stops working at once.
# - A request finds or creates the contact and makes a DRAFT booking; when the workspace has an API inbox, a
#   conversation with a private note tells the team. Nothing is ever sent to the customer.
class Tolzar::BookingRequest
  NONCE_KEY = 'tolzar_booking_request_nonce'.freeze
  EMAIL = /\A[^@\s]{1,64}@[^@\s]{1,190}\.[a-z]{2,24}\z/i
  MAX_NOTE = 500
  MAX_PEOPLE = 500

  def self.enabled?(account_id)
    Tolzar::Booking.enabled?(account_id) &&
      ENV.fetch('TOLZAR_BOOKING_REQUESTS_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
         .include?(account_id.to_i)
  end

  def self.nonce(account)
    (account.settings || {})[NONCE_KEY].to_s
  end

  def self.reset!(account)
    account.update!(settings: (account.settings || {}).merge(NONCE_KEY => SecureRandom.hex(16)))
  end

  def self.token(account)
    reset!(account) if nonce(account).empty?
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "tolzar-book:#{account.id}:#{nonce(account)}")
  end

  def self.url(account)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/tz/book/#{account.id}/#{token(account)}"
  end

  # The account, when the switch is on and the token matches its current link; nil otherwise.
  def self.verify(account_id, given)
    return unless enabled?(account_id) && given.to_s.length == 64

    account = Account.find_by(id: account_id)
    return unless account && !nonce(account).empty?
    return unless ActiveSupport::SecurityUtils.secure_compare(token(account), given.to_s)

    account
  end

  attr_reader :errors

  def initialize(account, params)
    @account = account
    @params = params.to_h.with_indifferent_access
    @errors = []
  end

  # The draft booking, or nil with errors (keys for tolzar.booking_request.errors).
  def perform
    validate
    return if @errors.any?

    contact = find_contact || create_contact
    booking = create_booking(contact)
    add_note(contact, booking)
    booking
  end

  private

  def validate
    @errors << 'date' unless date && date >= Date.current && date <= Date.current + 730
    @errors << 'people' unless people
    @errors << 'name' if name.blank?
    @errors << 'reach' unless email || phone || raw_reach.present?
    @errors << 'note' if @params[:note].to_s.length > MAX_NOTE
  end

  def date
    @date ||= Date.iso8601(@params[:date].to_s)
  rescue ArgumentError
    nil
  end

  def people
    value = Integer(@params[:people].to_s.strip, exception: false)
    value if value&.between?(1, MAX_PEOPLE)
  end

  def name
    @params[:name].to_s.strip.first(120)
  end

  def raw_reach
    @params[:reach].to_s.strip.first(255)
  end

  def email
    value = raw_reach.downcase
    value if value.match?(EMAIL)
  end

  # Only an international number (+…) goes on the contact (the contact model requires it); any other form stays
  # in the booking notes for the team.
  def phone
    value = raw_reach.gsub(/[^\d+]/, '')
    value if !raw_reach.include?('@') && value.match?(/\A\+[1-9]\d{5,14}\z/)
  end

  def note
    @params[:note].to_s.strip.first(MAX_NOTE)
  end

  def find_contact
    (email && @account.contacts.find_by(email: email)) || (phone && @account.contacts.find_by(phone_number: phone))
  end

  def create_contact
    @account.contacts.create!({ name: name, email: email, phone_number: phone }.compact)
  end

  def create_booking(contact)
    lines = [{ 'type' => 'service', 'description' => 'Booking request', 'unit_price' => '0', 'date' => date.iso8601, 'qty' => people }]
    notes = ["Booking request from the public form. Name: #{name}. Contact: #{raw_reach}", note.presence].compact.join("\n")
    booking = Tolzar::Booking.new(account: @account, contact: contact, currency: 'USD', status: 'draft',
                                  data: { 'lines' => lines, 'notes' => notes },
                                  history: [{ 'action' => 'requested', 'by' => nil, 'at' => Time.current.utc.iso8601 }])
    return booking.tap(&:save!) if booking.valid?

    # A note the document rules refuse (an ID number, say) is left out rather than losing the request.
    booking.data = { 'lines' => lines }
    booking.tap(&:save!)
  end

  # A private note for staff, only where the workspace has an API inbox to hold the conversation.
  def add_note(contact, booking)
    inbox = @account.inboxes.where(channel_type: 'Channel::Api').order(:id).first
    return unless inbox

    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |ci| ci.source_id = "book:#{SecureRandom.uuid}" }
    conversation = Conversation.create!(account_id: @account.id, inbox_id: inbox.id, contact_id: contact.id,
                                        contact_inbox_id: contact_inbox.id)
    booking.update!(conversation: conversation)
    conversation.messages.create!(account_id: @account.id, inbox_id: inbox.id, message_type: :outgoing, private: true,
                                  content: note_text(booking))
  end

  def note_text(booking)
    ["New booking request (draft booking ##{booking.id}). Nothing has been sent to the customer.",
     "Date: #{date.iso8601}", "People: #{people}", "Name: #{name}", "Contact: #{raw_reach}",
     note.presence && "Note: #{note}"].compact.join("\n")
  end
end
