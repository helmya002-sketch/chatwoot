# GET /tz/ical/:account_id/:user_id/:token.ics (round 4, c101; Tolzar::BookingCalendar): a person's private, read-only
# bookings feed for their calendar app. Public (calendar apps send no sign-in), so the token is the only key; any
# mismatch, a removed or deactivated person, or the switch off answers 404, the same for all.
class Tolzar::BookingCalendarController < ActionController::Base
  def show
    account_id = params[:account_id].to_i
    return head(:not_found) unless Tolzar::Booking.enabled?(account_id)
    token = params[:token].to_s.delete_suffix('.ics')
    return head(:not_found) unless Tolzar::BookingCalendar.verify(account_id, params[:user_id], token)

    response.headers['Cache-Control'] = 'private, max-age=900'
    send_data Tolzar::BookingCalendar.new(Account.find(account_id)).ics, type: 'text/calendar; charset=utf-8',
                                                                          disposition: 'inline', filename: 'bookings.ics'
  end
end
