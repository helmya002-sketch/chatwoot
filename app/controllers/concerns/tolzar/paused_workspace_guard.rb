# Tolzar billing v1: a paused workspace (trial ended, or a paid plan lapsed) is read-only in the account API.
# Reading still works, and so does starting a data export, so nothing is held hostage. Every other write
# (replies, notes, settings, invites) answers 402 workspace_paused until a plan is chosen. Incoming messages
# do not come through here (widget and channel webhooks), so customers' messages are still stored.
module Tolzar::PausedWorkspaceGuard
  extend ActiveSupport::Concern

  ALLOWED_WHILE_PAUSED = { 'api/v1/accounts/tolzar' => %w[export_start] }.freeze

  included do
    before_action :tolzar_refuse_writes_when_paused
  end

  private

  def tolzar_refuse_writes_when_paused
    return unless Tolzar::Subscription.enforced?
    return if request.get? || request.head? || Current.account.nil?
    return if ALLOWED_WHILE_PAUSED.fetch(params[:controller].to_s, []).include?(params[:action].to_s)

    subscription = Tolzar::Subscription.find_by(account_id: Current.account.id)
    return unless subscription&.paused?

    subscription.mark_paused!
    render json: { error: 'workspace_paused', subscription: subscription.view }, status: :payment_required
  end
end
