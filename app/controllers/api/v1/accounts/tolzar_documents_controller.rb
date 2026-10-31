# Tolzar booking documents API (Tolzar::Document), for TOLZAR_BOOKING_DOCS_ACCOUNTS workspaces (404 otherwise).
#   GET    tolzar/documents             the register (status, doc_type, q = number or contact name), newest first
#   GET    tolzar/documents/export      the register as CSV (administrators)
#   GET    tolzar/documents/:id
#   POST   tolzar/documents             a draft {doc_type, conversation_id (display id), currency, language, spec}
#   PATCH  tolzar/documents/:id         a draft's new spec (a new version)
#   POST   tolzar/documents/:id/issue   checks, then the gapless number
#   POST   tolzar/documents/:id/void    {reason} (administrators); the number stays
# Any member drafts and issues; nothing is sent to a customer from here.
class Api::V1::Accounts::TolzarDocumentsController < Api::V1::Accounts::BaseController
  PER_PAGE = 50

  before_action :ensure_enabled
  before_action :set_document, only: %i[show update issue void]
  before_action :ensure_admin, only: %i[void export]

  def index
    scope = Tolzar::Document.where(account_id: Current.account.id).includes(:contact, :conversation).register
    scope = scope.where(status: params[:status]) if Tolzar::Document::STATUSES.include?(params[:status])
    scope = scope.where(doc_type: params[:doc_type]) if Tolzar::DocumentSpec::TYPES.include?(params[:doc_type])
    if params[:q].present?
      like = "%#{Tolzar::Document.sanitize_sql_like(params[:q].to_s.first(80))}%"
      scope = scope.left_joins(:contact).where('tolzar_documents.number ILIKE :q OR contacts.name ILIKE :q', q: like)
    end
    page = [params[:page].to_i, 1].max
    rows = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    render json: { ok: true, page: page, documents: rows.map { |d| d.view.except(:spec, :history) } }
  end

  def show
    render json: { ok: true, document: @document.view }
  end

  def create
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id]) if params[:conversation_id].present?
    document = Tolzar::Document.new(
      account: Current.account, conversation: conversation, contact: conversation&.contact,
      doc_type: params[:doc_type].to_s, currency: params[:currency].to_s.upcase.presence || 'USD',
      language: params[:language].to_s.first(5).presence || 'en', spec: spec_param, created_by_id: Current.user.id,
      history: [{ 'action' => 'created', 'by' => Current.user.id, 'at' => Time.current.utc.iso8601, 'version' => 1 }]
    )
    return render(json: { ok: false, errors: document.errors.full_messages }, status: :unprocessable_entity) unless document.save

    render json: { ok: true, document: document.view }, status: :created
  end

  def update
    @document.revise!(spec_param, by: Current.user)
    render json: { ok: true, document: @document.view }
  rescue Tolzar::Document::Refused => e
    refused(e.message)
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def issue
    @document.issue!(by: Current.user)
    render json: { ok: true, document: @document.view }
  rescue Tolzar::Document::Refused => e
    refused(e.message)
  end

  def void
    @document.void!(reason: params[:reason], by: Current.user)
    render json: { ok: true, document: @document.view }
  rescue Tolzar::Document::Refused => e
    refused(e.message)
  end

  def export
    rows = Tolzar::Document.where(account_id: Current.account.id).where.not(number: nil).includes(:contact).order(:issued_at)
    csv = CSV.generate do |out|
      out << %w[number type status contact total currency paid payment_state issued_at voided_at void_reason]
      rows.each do |d|
        v = d.view
        out << [d.number, d.doc_type, d.status, d.contact&.name, format('%.2f', d.total_cents / 100.0), d.currency,
                format('%.2f', d.paid_cents / 100.0), v[:payment_state], d.issued_at&.utc&.iso8601, d.voided_at&.utc&.iso8601, d.void_reason]
      end
    end
    send_data csv, filename: "documents-#{Time.current.strftime('%Y%m%d')}.csv", type: 'text/csv'
  end

  private

  def ensure_enabled
    head :not_found unless Tolzar::Document.enabled?(Current.account.id)
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end

  def set_document
    @document = Tolzar::Document.find_by!(account_id: Current.account.id, id: params[:id])
  end

  def spec_param
    raw = params[:spec]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
  end

  def refused(message)
    render json: { ok: false, error: message }, status: :unprocessable_entity
  end
end
