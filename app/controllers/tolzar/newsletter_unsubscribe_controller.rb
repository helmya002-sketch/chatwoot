# Tolzar: the newsletter's unsubscribe link, PUBLIC (the user clicks it from an email, signed out).
#   GET  /tolzar/newsletter/unsubscribe/:token  a page with one button (mail scanners follow GET links; RFC 8058
#                                                says GET must not unsubscribe)
#   POST /tolzar/newsletter/unsubscribe/:token  unsubscribes: the button, or the mailbox provider's one-click
#                                                POST with body "List-Unsubscribe=One-Click" (no CSRF token exists)
# The signed token is the only credential and it can only opt that one user out of the newsletter.
class Tolzar::NewsletterUnsubscribeController < ActionController::Base
  skip_forgery_protection
  layout false
  around_action :in_the_users_language

  def show
    @user_id = Tolzar::NewsletterToken.user_id(params[:token])
    return render(:invalid, status: :not_found) if @user_id.nil?

    @done = Tolzar::NewsletterRecipient.find_by(user_id: @user_id)&.opted_out_at.present?
  end

  def create
    user_id = Tolzar::NewsletterToken.user_id(params[:token])
    return render(:invalid, status: :not_found) if user_id.nil?

    Tolzar::NewsletterRecipient.opt_out!(user_id)
    @done = true
    render :show
  end

  private

  def in_the_users_language(&)
    user = User.find_by(id: Tolzar::NewsletterToken.user_id(params[:token]))
    I18n.with_locale(user ? Tolzar::NewsletterAudience.locale_for(user) : I18n.default_locale, &)
  end
end
