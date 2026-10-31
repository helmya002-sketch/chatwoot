# Tolzar owner's daily digest (round 4, c89): once a day, for each TOLZAR_DIGEST_ACCOUNTS workspace, yesterday's and
# today's numbers to the workspace owner. One workspace failing never stops the others.
class Tolzar::DailyDigestJob < ApplicationJob
  queue_as :low

  def perform
    Tolzar::DailyDigest.accounts.each do |account_id|
      account = Account.find_by(id: account_id)
      owner = account && User.find_by(id: Tolzar::AccountOwner.user_id(account))
      next unless owner

      Current.account = account
      Tolzar::DigestMailer.daily([owner.email], Tolzar::DailyDigest.new(account).report).deliver_now
    rescue StandardError => e
      Rails.logger.error("[Tolzar] daily digest account=#{account_id} failed: #{e.class}")
    ensure
      Current.reset
    end
  end
end
