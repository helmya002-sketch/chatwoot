# Tolzar: who receives a newsletter. Only people who use the app (owner decision, 30 Oct 2026): confirmed users
# with an email and at least one workspace, minus opt-outs and suppressions, optionally one language.
# A user's language is their own UI language when set, else their first workspace's, else English.
class Tolzar::NewsletterAudience
  def initialize(locale: nil)
    @locale = locale.presence
  end

  def users
    scope = User.where.not(confirmed_at: nil)
                .where.not(email: [nil, ''])
                .where(id: AccountUser.select(:user_id))
                .where.not(id: Tolzar::NewsletterRecipient.blocked.select(:user_id))
    return scope.order(:id) if @locale.nil?

    scope.order(:id).select { |user| self.class.locale_for(user) == @locale }
  end

  def count
    users.size
  end

  def self.locale_for(user)
    own = (user.ui_settings || {})['locale'].presence
    return own.to_s if own && I18n.available_locales.map(&:to_s).include?(own.to_s)

    account_locale = user.accounts.order(:id).first&.locale
    account_locale.presence&.to_s || 'en'
  end
end
