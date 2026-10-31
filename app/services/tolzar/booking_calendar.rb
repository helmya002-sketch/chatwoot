# Tolzar bookings calendar feed (round 4, c101): a private, read-only iCal link per person and workspace, for
# TOLZAR_BOOKINGS_ACCOUNTS workspaces, so staff see bookings in their own calendar app.
# - The link carries HMAC-SHA256(secret_key_base, "tolzar-ical:<account>:<user>:<nonce>"); the nonce lives on the user
#   (custom_attributes tolzar_ical[<account>]). Reset = a new nonce, and the old link stops working at once.
# - Calendar apps copy what they fetch to their own servers, so a feed says little: "Booking #12 · Confirmed" and the
#   dates. No customer names, contacts, amounts or notes.
# - Confirmed and completed bookings with a start date, from 30 days back to a year ahead; all-day events.
class Tolzar::BookingCalendar
  STATUSES = %w[confirmed completed].freeze

  def self.nonce(user, account_id)
    (user.custom_attributes || {}).dig('tolzar_ical', account_id.to_s).to_s
  end

  def self.reset!(user, account_id)
    attrs = (user.custom_attributes || {}).deep_dup
    attrs['tolzar_ical'] = (attrs['tolzar_ical'] || {}).merge(account_id.to_s => SecureRandom.hex(16))
    user.update!(custom_attributes: attrs)
  end

  def self.token(user, account_id)
    reset!(user, account_id) if nonce(user, account_id).empty?
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "tolzar-ical:#{account_id}:#{user.id}:#{nonce(user, account_id)}")
  end

  # The user, when the token matches a current member of the workspace; nil otherwise.
  def self.verify(account_id, user_id, given)
    user = User.find_by(id: user_id)
    return unless user && given.to_s.length == 64 && !nonce(user, account_id).empty?
    return unless AccountUser.exists?(account_id: account_id, user_id: user.id) && user.active_for_authentication?
    return unless ActiveSupport::SecurityUtils.secure_compare(token(user, account_id), given.to_s)

    user
  end

  def initialize(account, now: Date.current)
    @account = account
    @now = now
  end

  def ics
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Tolzar//Bookings//EN', 'CALSCALE:GREGORIAN',
             "X-WR-CALNAME:#{escape(@account.name)} bookings"]
    bookings.each { |b| lines.concat(event(b)) }
    lines << 'END:VCALENDAR'
    "#{lines.join("\r\n")}\r\n"
  end

  private

  def bookings
    Tolzar::Booking.where(account_id: @account.id, status: STATUSES, starts_on: (@now - 30)..(@now + 365))
                   .order(:starts_on).limit(2000)
  end

  def event(booking)
    ends = [booking.ends_on || booking.starts_on, booking.starts_on].max + 1
    ['BEGIN:VEVENT', "UID:tolzar-booking-#{booking.id}@#{@account.id}", "DTSTAMP:#{booking.updated_at.utc.strftime('%Y%m%dT%H%M%SZ')}",
     "DTSTART;VALUE=DATE:#{booking.starts_on.strftime('%Y%m%d')}", "DTEND;VALUE=DATE:#{ends.strftime('%Y%m%d')}",
     "SUMMARY:Booking ##{booking.id} · #{booking.status.capitalize}", 'END:VEVENT']
  end

  def escape(text)
    text.to_s.gsub(/[\\;,]/) { |c| "\\#{c}" }.gsub(/[\r\n]+/, ' ')
  end
end
