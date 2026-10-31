# Tolzar bookings calendar link (round 4, c101; Tolzar::BookingCalendar), for the signed-in person only:
#   GET  tolzar/booking_calendar        {url}  their private feed link (made on first use)
#   POST tolzar/booking_calendar/reset  {url}  a new link; the old one stops working
# TOLZAR_BOOKINGS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarBookingCalendarController < Api::V1::Accounts::BaseController
  before_action { head(:not_found) unless Tolzar::Booking.enabled?(Current.account.id) }

  def show
    render json: { ok: true, url: feed_url }
  end

  def reset
    Tolzar::BookingCalendar.reset!(Current.user, Current.account.id)
    render json: { ok: true, url: feed_url }
  end

  private

  def feed_url
    token = Tolzar::BookingCalendar.token(Current.user, Current.account.id)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/tz/ical/#{Current.account.id}/#{Current.user.id}/#{token}.ics"
  end
end
