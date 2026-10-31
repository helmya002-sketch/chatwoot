# Tolzar bookings schedule (round 4, c102): GET tolzar/booking_schedule (Tolzar::BookingSchedule), who and what is busy
# per day for the next 14 days, with clashes flagged. Anyone in the workspace; TOLZAR_BOOKINGS_ACCOUNTS (404 otherwise).
class Api::V1::Accounts::TolzarBookingScheduleController < Api::V1::Accounts::BaseController
  def show
    return head(:not_found) unless Tolzar::Booking.enabled?(Current.account.id)

    render json: { ok: true }.merge(Tolzar::BookingSchedule.new(Current.account).report)
  end
end
