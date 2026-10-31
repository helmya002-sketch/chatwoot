# GET/POST /tz/quote/:document_id/:token (round 4, D2; Tolzar::QuoteAcceptance): the customer's quote acceptance
# page. Public (customers are signed out), so the token is the only key; a bad token or the switch off answers 404,
# the same for all. A void, expired or non-quote document shows "no longer valid". Accept makes a draft
# confirmation for staff; nothing is sent to anyone.
class Tolzar::QuoteAcceptancesController < ActionController::Base
  protect_from_forgery with: :exception
  layout false
  before_action :set_document

  def show
    render_page
  end

  def create
    Tolzar::QuoteAcceptance.accept!(@document) if @open || @accepted
    @accepted = Tolzar::QuoteAcceptance.accepted?(@document.reload)
    render_page
  rescue Tolzar::QuoteAcceptance::Refused
    @open = false
    render_page
  end

  private

  def render_page
    render :show, status: @open || @accepted ? :ok : :gone
  end

  def set_document
    @document = Tolzar::QuoteAcceptance.verify(params[:document_id].to_i, params[:token])
    return head(:not_found) unless @document

    @open = Tolzar::QuoteAcceptance.open?(@document)
    @accepted = Tolzar::QuoteAcceptance.accepted?(@document)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Robots-Tag'] = 'noindex'
  end
end
