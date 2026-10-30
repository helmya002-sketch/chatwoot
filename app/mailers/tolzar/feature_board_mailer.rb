# Tolzar feature board: "your idea shipped" and "your idea was merged" (Tolzar::FeatureBoardNotifyJob decides who
# gets them). It inherits the newsletter mailer only for its SMTP settings (NEWSLETTER_SMTP_*, NEWSLETTER_FROM),
# so board mail never uses the app's transactional SMTP. One message per user, in the user's language, with the
# newsletter's one-click unsubscribe (it stops these too). No tracking.
class Tolzar::FeatureBoardMailer < Tolzar::NewsletterMailer
  # Pinned like the parent's (never the app-wide setting, which falls back to sendmail when SMTP_ADDRESS is empty).
  self.delivery_method = Rails.env.test? ? :test : :smtp

  def shipped(idea, user)
    @idea = idea
    @explanation = idea.pinned_comment&.body
    @entry = idea.changelog_entry if idea.changelog_entry&.published_at
    board_mail(user, :shipped, title: idea.title)
  end

  def merged(duplicate, user)
    @duplicate = duplicate
    @idea = duplicate.merged_into
    board_mail(user, :merged, title: duplicate.title)
  end

  private

  def board_mail(user, kind, title:)
    @user = user
    @locale = Tolzar::NewsletterAudience.locale_for(user).presence_in(Tolzar::Idea::UI_LOCALES) || 'en'
    urls = Rails.application.routes.url_helpers
    @idea_url = urls.tolzar_feedback_idea_url(@idea, host: ENV.fetch('FRONTEND_URL'))
    @changelog_url = urls.tolzar_feedback_changelog_url(host: ENV.fetch('FRONTEND_URL'), anchor: @entry.anchor) if @entry
    @unsubscribe_url = Tolzar::NewsletterToken.unsubscribe_url(user.id)
    @postal_address = ENV.fetch('NEWSLETTER_POSTAL_ADDRESS')

    headers['List-Unsubscribe'] = "<#{@unsubscribe_url}>"
    headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
    headers['Auto-Submitted'] = 'auto-generated'

    I18n.with_locale(@locale) do
      mail(to: user.email, from: ENV.fetch('NEWSLETTER_FROM'), subject: I18n.t("tolzar.feedback.mail.#{kind}.subject", title: title)) do |format|
        format.text
        format.html
      end
    end
  end
end
