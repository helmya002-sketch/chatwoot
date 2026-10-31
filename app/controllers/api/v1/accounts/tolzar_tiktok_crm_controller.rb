# Tolzar TikTok CRM events (Tolzar::AdPlatformLink): the workspace owner links the TikTok event set, the token
# (write-only) and which pipeline stage sends which event. 404 unless the workspace is in TOLZAR_TIKTOK_CRM_EVENTS.
#   GET  tolzar/tiktok_crm   the link (token "set"/"not set") and the workspace's stages
#   POST tolzar/tiktok_crm   {enabled, event_set_id, token (empty keeps it), stage_events}
class Api::V1::Accounts::TolzarTiktokCrmController < Api::V1::Accounts::BaseController
  before_action :ensure_allowed
  before_action :ensure_owner

  def show
    link = Tolzar::AdPlatformLink.find_by(account_id: Current.account.id, platform: 'tiktok')
    render json: { ok: true, link: link&.view, stages: Tolzar::PipelineSettings.stage_keys(Current.account) }
  end

  def save
    link = Tolzar::AdPlatformLink.find_or_initialize_by(account_id: Current.account.id, platform: 'tiktok')
    link.assign_attributes(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]) == true,
                           event_set_id: params[:event_set_id].to_s.strip.presence, stage_events: stage_events,
                           updated_by_id: Current.user.id)
    link.token = params[:token].to_s.strip if params[:token].present?
    return render(json: { ok: false, errors: link.errors.full_messages }, status: :unprocessable_entity) unless link.save

    render json: { ok: true, link: link.view }
  end

  private

  def stage_events
    raw = params[:stage_events]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.to_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }.compact_blank : {}
  end

  def ensure_allowed
    head :not_found unless Tolzar::AdPlatformLink.allowed?(Current.account.id)
  end

  def ensure_owner
    return if Tolzar::AccountOwner.owner?(Current.account, Current.user)

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end
end
