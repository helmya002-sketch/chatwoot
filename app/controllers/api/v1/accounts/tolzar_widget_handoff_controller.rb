# Tolzar own widget hand-off links (Tolzar::WidgetHandoff) per website inbox.
#   GET  tolzar/widget_handoff?inbox_id=   the links (any administrator)
#   POST tolzar/widget_handoff             {inbox_id, whatsapp: "+20…", instagram: "handle", telegram: "handle"} (owner)
class Api::V1::Accounts::TolzarWidgetHandoffController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :ensure_owner, only: :save
  before_action :set_inbox

  def show
    render json: { ok: true, values: Tolzar::WidgetHandoff.for_inbox(@inbox), links: Tolzar::WidgetHandoff.links(@inbox) }
  end

  def save
    values, errors = Tolzar::WidgetHandoff.validate(params)
    return render(json: { ok: false, errors: errors }, status: :unprocessable_entity) if errors.any?

    Tolzar::WidgetHandoff.save!(@inbox, values)
    render json: { ok: true, values: values, links: Tolzar::WidgetHandoff.links(@inbox) }
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find_by(id: params[:inbox_id], channel_type: 'Channel::WebWidget')
    head :not_found unless @inbox
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'unauthorized' }, status: :unauthorized
  end

  def ensure_owner
    return if Tolzar::AccountOwner.owner?(Current.account, Current.user)

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end
end
