# Tolzar weekly staff report (round 4, c98): Mondays, for each TOLZAR_WEEKLY_REPORT_ACCOUNTS workspace, the last 7 days
# to its administrators. One workspace failing never stops the others.
class Tolzar::WeeklyReportJob < ApplicationJob
  queue_as :low

  def perform
    Tolzar::WeeklyReport.accounts.each do |account_id|
      account = Account.find_by(id: account_id)
      to = account ? Tolzar::WeeklyReport.recipients(account) : []
      next if to.empty?

      Current.account = account
      Tolzar::DigestMailer.weekly(to, Tolzar::WeeklyReport.new(account).report).deliver_now
    rescue StandardError => e
      Rails.logger.error("[Tolzar] weekly report account=#{account_id} failed: #{e.class}")
    ensure
      Current.reset
    end
  end
end
