# Tolzar native bookings API (Tolzar::Booking), for TOLZAR_BOOKINGS_ACCOUNTS workspaces (404 otherwise).
#   GET   tolzar/bookings                ?status= &from= &to= (dates) &contact_id= ; newest first
#   GET   tolzar/bookings/agenda         today and the next 14 days: bookings per day, with balances due
#   GET   tolzar/bookings/:id
#   POST  tolzar/bookings                {conversation_id (display id) | contact_id, currency, data}
#   PATCH tolzar/bookings/:id            {data} (draft or confirmed)
#   POST  tolzar/bookings/:id/status     {to: confirmed | completed | cancelled}
#   POST  tolzar/bookings/:id/payment    {amount, date, method, reference}: a record; Tolzar never charges
#   POST  tolzar/bookings/:id/document   {doc_type}: a draft voucher / confirmation from the booking
class Api::V1::Accounts::TolzarBookingsController < Api::V1::Accounts::BaseController
  AGENDA_DAYS = 14

  before_action :ensure_enabled
  before_action :set_booking, only: %i[show update change_status payment document]

  def index
    scope = bookings.includes(:contact, :conversation).order(created_at: :desc)
    scope = scope.where(status: params[:status]) if Tolzar::Booking::STATUSES.include?(params[:status])
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    from = date(params[:from])
    to = date(params[:to])
    scope = scope.between(from || Date.new(2000), to || Date.new(2999)) if from || to
    render json: { ok: true, bookings: scope.limit(200).map { |b| b.view.except(:data, :history) } }
  end

  def agenda
    today = Date.current
    rows = bookings.where.not(status: 'cancelled').between(today, today + AGENDA_DAYS).includes(:contact).to_a
    days = (today..(today + AGENDA_DAYS)).map do |day|
      list = rows.select { |b| b.starts_on && b.starts_on <= day && (b.ends_on || b.starts_on) >= day }
      { date: day, bookings: list.map { |b| b.view.slice(:id, :status, :contact_name, :currency, :balance_cents) } }
    end
    render json: { ok: true, days: days, balances_due: rows.sum { |b| [b.total_cents - b.paid_cents, 0].max } }
  end

  def show
    render json: { ok: true, booking: @booking.view }
  end

  def create
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id]) if params[:conversation_id].present?
    contact = conversation&.contact || (Current.account.contacts.find_by(id: params[:contact_id]) if params[:contact_id].present?)
    booking = bookings.new(contact: contact, conversation: conversation, currency: params[:currency].to_s.upcase.presence || 'USD',
                           data: data_param, created_by_id: Current.user.id,
                           history: [{ 'action' => 'created', 'by' => Current.user.id, 'at' => Time.current.utc.iso8601 }])
    return render(json: { ok: false, errors: booking.errors.full_messages }, status: :unprocessable_entity) unless booking.save

    render json: { ok: true, booking: booking.view }, status: :created
  end

  def update
    return refused('a completed or cancelled booking is closed') unless %w[draft confirmed].include?(@booking.status)

    @booking.data = data_param
    @booking.history = Array(@booking.history) + [{ 'action' => 'edited', 'by' => Current.user.id, 'at' => Time.current.utc.iso8601 }]
    return render(json: { ok: false, errors: @booking.errors.full_messages }, status: :unprocessable_entity) unless @booking.save

    render json: { ok: true, booking: @booking.view }
  end

  def change_status
    @booking.move!(params[:to].to_s, by: Current.user)
    render json: { ok: true, booking: @booking.view }
  rescue Tolzar::Booking::Refused => e
    refused(e.message)
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def payment
    @booking.record_payment!(amount: params[:amount], date: date(params[:date]) || Date.current, method: params[:method],
                             reference: params[:reference], by: Current.user)
    render json: { ok: true, booking: @booking.view }
  rescue Tolzar::Booking::Refused => e
    refused(e.message)
  end

  def document
    return head(:not_found) unless Tolzar::Document.enabled?(Current.account.id)
    return refused('voucher or confirmation only') unless %w[voucher confirmation payment_summary].include?(params[:doc_type])

    doc = @booking.to_document!(doc_type: params[:doc_type], by: Current.user)
    render json: { ok: true, document: doc.view }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def bookings
    Tolzar::Booking.where(account_id: Current.account.id)
  end

  def ensure_enabled
    head :not_found unless Tolzar::Booking.enabled?(Current.account.id)
  end

  def set_booking
    @booking = bookings.find(params[:id])
  end

  def data_param
    raw = params[:data]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
  end

  def date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def refused(message)
    render json: { ok: false, error: message }, status: :unprocessable_entity
  end
end
