# Tolzar billing v1, daily: a workspace paused for the full 30-day data hold is purged (brain rows, then the
# Chatwoot side, Tolzar::WorkspacePurge). Only with TOLZAR_BILLING_ENFORCE=true; internal workspaces never
# pause. Before that, paused workspaces get their purge date stamped so the Owner's warnings can be sent.
class Tolzar::SubscriptionPurgeJob < ApplicationJob
  queue_as :low

  def perform(now = Time.current)
    return unless Tolzar::Subscription.enforced?

    Tolzar::Subscription.where(purged_at: nil).where.not(plan: 'internal').find_each do |sub|
      sub.mark_paused!(now)
      next unless sub.state(now) == 'purge_scheduled'

      Tolzar::WorkspacePurge.new(account: sub.account, dry_run: false).perform
    rescue Tolzar::WorkspacePurge::Refused => e
      Rails.logger.error("[Tolzar] billing purge refused for account #{sub.account_id}: #{e.message}")
    end
  end
end
