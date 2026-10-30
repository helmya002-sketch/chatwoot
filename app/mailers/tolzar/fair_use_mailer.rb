# Tolzar fair use (Tolzar::FairUse): the Owner's notice at 80% and 100% of the plan's monthly AI replies, and
# Tolzar's own alert. Soft limit: the mails say the AI keeps answering and nothing is charged.
class Tolzar::FairUseMailer < AdministratorNotifications::BaseMailer
  def notice(to, meta)
    subject = I18n.t("tolzar.fair_use.mail.#{meta['level']}.subject", workspace: meta['workspace'])
    url = "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{Current.account.id}/tolzar-settings"
    send_notification(subject, to: to, action_url: url, meta: meta)
  end

  def alert(to, meta)
    subject = "[Tolzar fair use] #{meta['level']}: #{meta['workspace']} (#{meta['account_id']}) " \
              "#{meta['used']}/#{meta['allowance']} #{meta['plan']} #{meta['month']}"
    send_notification(subject, to: to, meta: meta)
  end
end
