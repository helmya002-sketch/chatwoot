# Tolzar quote acceptance link (round 4, D2; Tolzar::QuoteAcceptance), any workspace member:
#   POST tolzar/documents/:id/accept_link  {url}  the issued quote's public acceptance link (made on first use)
# Staff pass the link on themselves; nothing is sent. Tolzar::Document + TOLZAR_QUOTE_ACCEPT_ACCOUNTS (404 otherwise).
class Api::V1::Accounts::TolzarQuoteAcceptLinkController < Api::V1::Accounts::BaseController
  before_action { head(:not_found) unless Tolzar::QuoteAcceptance.enabled?(Current.account.id) }

  def create
    document = Tolzar::Document.find_by!(account_id: Current.account.id, id: params[:id])
    unless Tolzar::QuoteAcceptance.open?(document)
      return render(json: { ok: false, error: 'only an issued quote that is still valid' }, status: :unprocessable_entity)
    end

    render json: { ok: true, url: Tolzar::QuoteAcceptance.url(document) }
  end
end
