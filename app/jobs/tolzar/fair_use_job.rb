# Tolzar fair use, hourly (Tolzar::FairUse; only with TOLZAR_FAIR_USE=true): every trial or paid workspace's AI
# replies this month against its plan's allowance. Soft: it only stores the state and notifies, never refuses.
class Tolzar::FairUseJob < ApplicationJob
  queue_as :low

  def perform
    return unless Tolzar::FairUse.enabled?

    Tolzar::Subscription.where(purged_at: nil, plan: Tolzar::FairUse.allowances.keys).includes(:account).find_each do |sub|
      Tolzar::FairUse.new(sub).check!
    rescue StandardError => e
      Rails.logger.error("[Tolzar] fair use check failed for account #{sub.account_id}: #{e.class}: #{e.message}")
    end
  end
end
