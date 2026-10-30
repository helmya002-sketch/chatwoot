# Tolzar (readiness gap 22): a customer's Manager is a Chatwoot administrator underneath, so outside Tolzar's
# own screens it could delete inboxes or reset bot tokens. These Chatwoot admin actions are Owner-only:
# creating or deleting inboxes, every agent-bot / webhook / integration write, deleting a member, making
# someone an administrator, and the workspace's own settings. The Owner is the account owner
# (Tolzar::AccountOwner) or an administrator the brain's role table marks "owner" (cached 60 s); every other
# administrator is a Manager. Agents never reach these (Chatwoot's own policies refuse them first).
module Tolzar::OwnerOnlyAdminGuard
  extend ActiveSupport::Concern

  OWNER_ONLY = {
    'api/v1/accounts/inboxes' => %w[create destroy set_agent_bot],
    'api/v1/accounts/agent_bots' => %w[create update destroy reset_access_token],
    'api/v1/accounts/webhooks' => %w[create update destroy],
    'api/v1/accounts/integrations/apps' => %w[create update destroy],
    'api/v1/accounts/integrations/hooks' => %w[create update destroy],
    'api/v1/accounts/agents' => %w[destroy],
    'api/v1/accounts' => %w[update]
  }.freeze
  ADMIN_PROMOTION = { 'api/v1/accounts/agents' => %w[create update bulk_create] }.freeze

  included do
    before_action :tolzar_owner_only_admin_action
  end

  private

  def tolzar_owner_only_admin_action
    return unless tolzar_gated_action?

    account = Current.account || (defined?(@account) && @account)
    account_user = account && account.account_users.find_by(user_id: Current.user&.id)
    return unless account_user&.administrator?
    return if Tolzar::OwnerOnlyAdminGuard.owner?(account, account_user.user_id)

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end

  def tolzar_gated_action?
    controller, action = params[:controller].to_s, params[:action].to_s
    return true if OWNER_ONLY.fetch(controller, []).include?(action)

    ADMIN_PROMOTION.fetch(controller, []).include?(action) && params[:role].to_s == 'administrator'
  end

  def self.owner?(account, user_id)
    return true if Tolzar::AccountOwner.user_id(account) == user_id

    roles = Rails.cache.fetch("tolzar:roles:#{account.id}", expires_in: 60.seconds) do
      res = Tolzar::BrainClient.get("/roles?account_id=#{account.id}&owner_user_id=#{Tolzar::AccountOwner.user_id(account)}",
                                    account_id: account.id)
      res.is_a?(Hash) ? (res['roles'] || {}) : {}
    end
    roles[user_id.to_s] == 'owner'
  rescue StandardError
    false
  end
end
