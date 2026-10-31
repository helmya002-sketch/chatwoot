# Tolzar::TrialMail's mail: the trial requester's "what happens next" (plain text and HTML, en / de).
class Tolzar::TrialMailer < ActionMailer::Base
  # Plain ActionMailer (no account, no liquid / DB templates): a fixed text for a visitor who has no workspace yet.
  prepend_view_path Rails.root.join('app/views/mailers')
  SUBJECTS = { 'en' => 'Your Tolzar trial: what happens next', 'de' => 'Ihre Tolzar-Testphase: so geht es weiter' }.freeze

  def confirmation(email, first_name, lang)
    @first_name = first_name
    @lang = lang
    mail(to: email, from: ENV.fetch('TOLZAR_TRIAL_MAIL_FROM'), reply_to: ENV['TOLZAR_TRIAL_MAIL_REPLY_TO'].presence,
         subject: SUBJECTS.fetch(lang, SUBJECTS['en'])) do |format|
      format.text { render "confirmation_#{lang}" }
      format.html { render "confirmation_#{lang}_html", layout: false }
    end
  end
end
