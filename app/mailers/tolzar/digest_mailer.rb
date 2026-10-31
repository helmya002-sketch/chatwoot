# Tolzar owner's daily digest (round 4, c89; Tolzar::DailyDigest): internal, to the workspace owner only.
class Tolzar::DigestMailer < AdministratorNotifications::BaseMailer
  def daily(to, meta)
    subject = I18n.t('tolzar.digest.subject', workspace: meta['workspace'], day: meta['day'])
    url = "#{(ENV['TOLZAR_MAIL_LINK_URL'].presence || ENV.fetch('FRONTEND_URL', nil)).to_s.chomp('/')}/app/accounts/#{Current.account.id}/dashboard"
    send_notification(subject, to: to, action_url: url, meta: meta)
  end
end
