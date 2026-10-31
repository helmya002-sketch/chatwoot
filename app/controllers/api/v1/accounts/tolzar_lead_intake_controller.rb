# Tolzar lead intake (Tolzar::LeadIntake): the workspace owner reads each API inbox's lead URL to paste into TikTok
# Instant Forms' CRM webhook, a connector or a website form. Owner-only, because the URL carries the secret.
class Api::V1::Accounts::TolzarLeadIntakeController < Api::V1::Accounts::BaseController
  before_action :ensure_owner

  def show
    enabled = Tolzar::LeadIntake.accounts.include?(Current.account.id)
    inboxes = Current.account.inboxes.where(channel_type: 'Channel::Api').order(:id)
    render json: { ok: true, enabled: enabled,
                   inboxes: inboxes.map { |i| { id: i.id, name: i.name, url: (Tolzar::LeadIntake.url(i) if enabled) }.compact } }
  end

  private

  def ensure_owner
    return if Tolzar::AccountOwner.owner?(Current.account, Current.user)

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end
end
