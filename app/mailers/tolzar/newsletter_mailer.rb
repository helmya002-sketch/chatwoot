# Tolzar: the newsletter to the app's own users. It sends through its OWN SMTP server (NEWSLETTER_SMTP_*: Postal
# on news.<domain>), never the app's transactional SMTP, so app mail keeps its own sending reputation.
# Every message carries the one-click unsubscribe of RFC 8058 (List-Unsubscribe + List-Unsubscribe-Post), a
# footer saying why the user gets it, the sender's postal address and the privacy link. No tracking pixel,
# no rewritten links.
class Tolzar::NewsletterMailer < ActionMailer::Base
  layout false

  unless Rails.env.test?
    self.delivery_method = :smtp
    self.smtp_settings = {
      address: ENV.fetch('NEWSLETTER_SMTP_ADDRESS', 'localhost'),
      port: ENV.fetch('NEWSLETTER_SMTP_PORT', '1025').to_i,
      domain: ENV.fetch('NEWSLETTER_SMTP_DOMAIN', 'localhost'),
      user_name: ENV.fetch('NEWSLETTER_SMTP_USERNAME', nil).presence,
      password: ENV.fetch('NEWSLETTER_SMTP_PASSWORD', nil).presence,
      authentication: ENV.fetch('NEWSLETTER_SMTP_USERNAME', nil).present? ? :plain : nil,
      enable_starttls_auto: ActiveModel::Type::Boolean.new.cast(ENV.fetch('NEWSLETTER_SMTP_STARTTLS', 'true'))
    }.compact
  end

  def issue(delivery)
    @newsletter = delivery.newsletter
    @user = delivery.user
    @locale = Tolzar::NewsletterAudience.locale_for(@user)
    @unsubscribe_url = Tolzar::NewsletterToken.unsubscribe_url(@user.id)
    @postal_address = ENV.fetch('NEWSLETTER_POSTAL_ADDRESS')
    @privacy_url = ENV.fetch('NEWSLETTER_PRIVACY_URL')

    headers['List-Unsubscribe'] = "<#{@unsubscribe_url}>"
    headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
    headers['List-Id'] = "Tolzar newsletter <newsletter.#{ENV.fetch('NEWSLETTER_SMTP_DOMAIN', 'localhost')}>"
    headers['Precedence'] = 'bulk'
    headers['Auto-Submitted'] = 'auto-generated'

    I18n.with_locale(@locale) do
      mail(to: delivery.email, from: ENV.fetch('NEWSLETTER_FROM'), subject: @newsletter.subject,
           message_id: "<#{delivery.message_id}>") do |format|
        format.text
        format.html
      end
    end
  end
end
