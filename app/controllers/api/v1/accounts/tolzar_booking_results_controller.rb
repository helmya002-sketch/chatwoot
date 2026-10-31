# Tolzar bookings: results and export for administrators.
#   GET tolzar/booking_results  ?days=7|30|90  Results → Bookings card (Tolzar::BookingResults); 404 when both
#                                              documents and bookings are off for the workspace
#   GET tolzar/bookings/export  ?from=&to=     the bookings as CSV (bookings switch on): one row per booking, no
#                                              notes and no guest names beyond the contact's name
class Api::V1::Accounts::TolzarBookingResultsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin

  def show
    return head(:not_found) unless Tolzar::Document.enabled?(Current.account.id) || Tolzar::Booking.enabled?(Current.account.id)

    render json: { ok: true }.merge(Tolzar::BookingResults.new(Current.account, days: params[:days]).report)
  end

  def export
    return head(:not_found) unless Tolzar::Booking.enabled?(Current.account.id)

    scope = Tolzar::Booking.where(account_id: Current.account.id).includes(:contact, :conversation).order(:starts_on, :id)
    from = date(params[:from])
    to = date(params[:to])
    scope = scope.between(from || Date.new(2000), to || Date.new(2999)) if from || to
    send_data csv(scope), filename: "bookings-#{Time.current.strftime('%Y%m%d')}.csv", type: 'text/csv'
  end

  private

  def csv(scope)
    money = ->(cents) { format('%.2f', cents.to_i / 100.0) }
    CSV.generate do |out|
      out << %w[id status starts_on ends_on contact conversation currency total paid due payment_state created_at]
      scope.find_each do |b|
        v = b.view
        out << [b.id, b.status, b.starts_on, b.ends_on, Tolzar::CsvCell.safe(b.contact&.name), b.conversation&.display_id, b.currency,
                money.call(b.total_cents), money.call(b.paid_cents), money.call(v[:balance_cents]), v[:payment_state],
                b.created_at.utc.iso8601]
      end
    end
  end

  def date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end
end
