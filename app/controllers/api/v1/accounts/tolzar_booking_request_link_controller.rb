# Tolzar booking request link (round 4, D1; Tolzar::BookingRequest), administrators only:
#   GET  tolzar/booking_request_link        {url}  the workspace's public booking request form (made on first use)
#   POST tolzar/booking_request_link/reset  {url}  a new link; the old one stops working
# TOLZAR_BOOKINGS_ACCOUNTS + TOLZAR_BOOKING_REQUESTS_ACCOUNTS workspaces (404 otherwise).
class Api::V1::Accounts::TolzarBookingRequestLinkController < Api::V1::Accounts::BaseController
  before_action { head(:not_found) unless Tolzar::BookingRequest.enabled?(Current.account.id) }
  before_action do
    render(json: { ok: false, error: 'unauthorized' }, status: :unauthorized) unless Current.account_user&.administrator?
  end

  def show
    render json: { ok: true, url: Tolzar::BookingRequest.url(Current.account) }
  end

  def reset
    Tolzar::BookingRequest.reset!(Current.account)
    render json: { ok: true, url: Tolzar::BookingRequest.url(Current.account) }
  end
end
