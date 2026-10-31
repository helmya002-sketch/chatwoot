# GET/POST /tz/book/:account_id/:token (round 4, D1; Tolzar::BookingRequest): a workspace's public booking request
# form. Public (customers are signed out), so the token is the only key; a bad token or the switch off answers 404,
# the same for all. A filled honeypot field gets the thank-you page and nothing is saved. Nothing is sent to anyone.
class Tolzar::BookingRequestsController < ActionController::Base
  protect_from_forgery with: :exception
  layout false
  before_action :set_account

  def show
    @values = {}
  end

  def create
    return render(:thanks) if params[:website].present?

    form = Tolzar::BookingRequest.new(@account, form_params)
    return render(:thanks) if form.perform

    @errors = form.errors
    @values = form_params.to_h
    render :show, status: :unprocessable_entity
  end

  private

  def form_params
    params.permit(:date, :people, :name, :reach, :note)
  end

  def set_account
    @account = Tolzar::BookingRequest.verify(params[:account_id].to_i, params[:token])
    return head(:not_found) unless @account

    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Robots-Tag'] = 'noindex'
  end
end
