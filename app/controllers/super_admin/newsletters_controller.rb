# Tolzar: the newsletter page of the super admin console. Write an issue in Markdown, preview it as a user
# will see it, send a test to yourself, then send it to every user who uses the app and has not opted out.
# Sending to users is refused until NEWSLETTER_ENABLED=true (set by Server ops once Postal and the DNS exist,
# on the owner's go). Opt-outs are the users' own; a super admin can only suppress or unsuppress an address.
class SuperAdmin::NewslettersController < SuperAdmin::ApplicationController
  REQUIRED_ENV = %w[NEWSLETTER_FROM NEWSLETTER_SMTP_DOMAIN NEWSLETTER_POSTAL_ADDRESS NEWSLETTER_PRIVACY_URL FRONTEND_URL].freeze

  def show
    @newsletters = Tolzar::Newsletter.order(id: :desc).limit(20)
    @newsletter = params[:id].present? ? Tolzar::Newsletter.find(params[:id]) : Tolzar::Newsletter.new
    @missing_env = REQUIRED_ENV.select { |key| ENV[key].blank? }
    @enabled = Tolzar::NewsletterSendJob.enabled?
    @audience_count = Tolzar::NewsletterAudience.new(locale: @newsletter.locale).count
    @opted_out = Tolzar::NewsletterRecipient.where.not(opted_out_at: nil).count
    @suppressed = Tolzar::NewsletterRecipient.where.not(suppressed_at: nil).count
    @preview_html = preview_html if @newsletter.persisted? && @missing_env.empty?
  end

  def create
    newsletter = Tolzar::Newsletter.new(newsletter_params.merge(created_by_id: current_super_admin.id))
    if newsletter.save
      redirect_to super_admin_newsletter_path(id: newsletter.id), notice: t('super_admin.newsletter.saved')
    else
      redirect_to super_admin_newsletter_path, alert: newsletter.errors.full_messages.to_sentence
    end
  end

  def update
    newsletter = Tolzar::Newsletter.find(params[:id])
    if newsletter.update(newsletter_params)
      redirect_to super_admin_newsletter_path(id: newsletter.id), notice: t('super_admin.newsletter.saved')
    else
      redirect_to super_admin_newsletter_path(id: newsletter.id), alert: newsletter.errors.full_messages.to_sentence
    end
  end

  # One copy to the signed-in super admin's own address, now, whatever NEWSLETTER_ENABLED says.
  def test_send
    newsletter = Tolzar::Newsletter.find(params[:id])
    Tolzar::NewsletterMailer.issue(preview_delivery(newsletter)).deliver_now
    log_action("test-sent newsletter #{newsletter.id}")
    redirect_to super_admin_newsletter_path(id: newsletter.id),
                notice: t('super_admin.newsletter.test_sent', email: ERB::Util.html_escape(current_super_admin.email))
  end

  def deliver
    newsletter = Tolzar::Newsletter.find(params[:id])
    return redirect_back_to(newsletter, alert: t('super_admin.newsletter.disabled')) unless Tolzar::NewsletterSendJob.enabled?
    return redirect_back_to(newsletter, alert: t('super_admin.newsletter.not_a_draft')) unless newsletter.draft?
    return redirect_back_to(newsletter, alert: t('super_admin.newsletter.confirm_needed')) unless params[:confirm] == 'SEND'

    Tolzar::NewsletterSendJob.perform_later(newsletter.id)
    log_action("queued newsletter #{newsletter.id} (locale #{newsletter.locale || 'all'})")
    redirect_back_to(newsletter, notice: t('super_admin.newsletter.queued'))
  end

  # Suppress (a complaint that reached abuse@, or by hand) or unsuppress one address. Opt-outs stay as they are.
  def suppression
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    return redirect_to(super_admin_newsletter_path, alert: t('super_admin.newsletter.user_not_found')) if user.nil?

    if params[:op] == 'unsuppress'
      Tolzar::NewsletterRecipient.find_by(user_id: user.id)&.unsuppress!
    else
      reason = params[:reason].in?(%w[complaint super_admin]) ? params[:reason] : 'super_admin'
      Tolzar::NewsletterRecipient.suppress!(user.id, reason)
    end
    log_action("#{params[:op] == 'unsuppress' ? 'unsuppressed' : 'suppressed'} user #{user.id}")
    redirect_to super_admin_newsletter_path, notice: t('super_admin.newsletter.suppression_saved')
  end

  private

  def newsletter_params
    params.require(:newsletter).permit(:subject, :body_markdown, :locale)
  end

  def preview_delivery(newsletter)
    Tolzar::NewsletterDelivery.new(newsletter: newsletter, user: current_super_admin, email: current_super_admin.email,
                                   message_id: "tolzar-nl-test-#{newsletter.id}-#{SecureRandom.hex(6)}@#{ENV.fetch('NEWSLETTER_SMTP_DOMAIN')}")
  end

  def preview_html
    Tolzar::NewsletterMailer.issue(preview_delivery(@newsletter)).message.html_part.body.decoded
  end

  def redirect_back_to(newsletter, **flash)
    redirect_to super_admin_newsletter_path(id: newsletter.id), **flash
  end

  def log_action(message)
    Rails.logger.info("[SuperAdmin] newsletter #{message} (actor_id=#{current_super_admin.id})")
  end
end
