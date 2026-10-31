# Tolzar booking-system connector API (Tolzar::BookingConnector), for TOLZAR_BOOKING_CONNECTOR workspaces (404 else).
#   GET    tolzar/booking_connector              the connection (the token reads "set"; never returned)
#   POST   tolzar/booking_connector              {adapter, base_url, token} (owner; an empty token keeps the stored one)
#   POST   tolzar/booking_connector/test         a read call that proves it (owner)
#   POST   tolzar/booking_connector/disconnect   removes the connection (owner)
#   GET    tolzar/booking_connector/bookings     ?contact_id= the guest's bookings there (any member, read-only)
#   POST   tolzar/booking_connector/draft        {document_id} a DRAFT booking there from a Tolzar document (any member)
# Tolzar never confirms, prices or charges in the booking system.
class Api::V1::Accounts::TolzarBookingConnectorController < Api::V1::Accounts::BaseController
  before_action :ensure_enabled
  before_action :ensure_owner, only: %i[save check disconnect]
  before_action :set_connector, only: %i[check disconnect bookings draft]

  def show
    connector = Tolzar::BookingConnector.find_by(account_id: Current.account.id)
    render json: { ok: true, connected: connector.present?, connector: connector&.view,
                   adapters: Tolzar::BookingConnector::ADAPTERS.keys }
  end

  def save
    connector = Tolzar::BookingConnector.find_or_initialize_by(account_id: Current.account.id)
    connector.assign_attributes(adapter: params[:adapter].to_s, base_url: params[:base_url].to_s.strip, updated_by_id: Current.user.id)
    connector.token = params[:token].to_s.strip if params[:token].present?
    return render(json: { ok: false, errors: connector.errors.full_messages }, status: :unprocessable_entity) unless connector.save

    render json: { ok: true, connector: connector.view }
  end

  def check
    render json: @connector.test!.merge(connector: @connector.view)
  end

  def disconnect
    @connector.destroy!
    render json: { ok: true, connected: false }
  end

  def bookings
    contact = Current.account.contacts.find(params[:contact_id])
    return render(json: { ok: true, bookings: [] }) if contact.phone_number.blank? && contact.email.blank?

    list = @connector.client.bookings(phone: contact.phone_number.presence)
    render json: { ok: true, bookings: list.first(50) }
  rescue StandardError => e
    raise if e.is_a?(ActiveRecord::RecordNotFound)

    render json: { ok: false, error: e.message.to_s.first(200) }, status: :bad_gateway
  end

  def draft
    document = Tolzar::Document.find_by!(account_id: Current.account.id, id: params[:document_id])
    body, skipped = Tolzar::BookingConnectors::FromDocument.new(document).build
    out = @connector.client.create_draft(body)
    document.update!(history: Array(document.history) + [{ 'action' => 'sent_to_booking_system', 'by' => Current.user.id,
                                                          'at' => Time.current.utc.iso8601, 'version' => document.version }])
    render json: { ok: true, booking: out.slice('voucher_no', 'id', 'status'), skipped: skipped }
  rescue Tolzar::BookingConnectors::FromDocument::Refused => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    raise if e.is_a?(ActiveRecord::RecordNotFound)

    render json: { ok: false, error: e.message.to_s.first(200) }, status: :bad_gateway
  end

  private

  def ensure_enabled
    head :not_found unless Tolzar::BookingConnector.enabled?(Current.account.id)
  end

  def ensure_owner
    return if Tolzar::AccountOwner.owner?(Current.account, Current.user)

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end

  def set_connector
    @connector = Tolzar::BookingConnector.find_by(account_id: Current.account.id)
    render json: { ok: false, error: 'not_connected' }, status: :not_found unless @connector
  end
end
