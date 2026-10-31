# Tolzar site trial form: the instant "what happens next" mail to the person who asked for a trial (launch lane,
# conversion blueprint, 31 Oct). Off unless TOLZAR_TRIAL_MAIL_FROM is set (the sender, e.g.
# "Adam from Tolzar <noreply@tolzar.com>"). Sent only for topic=trial, only to the address typed in the form, at most
# once per address a day (the form cannot be used to mail a stranger repeatedly), with a fixed text: nothing the
# visitor typed is echoed except their first name.
module Tolzar::TrialMail
  module_function

  LANGS = %w[en de].freeze

  def enabled?
    ENV['TOLZAR_TRIAL_MAIL_FROM'].present?
  end

  def deliver_later(form)
    return unless enabled?

    email = form[:email].to_s.downcase
    key = "tolzar:trial_mail:#{Digest::SHA256.hexdigest(email)}:#{Time.current.utc.to_date}"
    return unless Redis::Alfred.set(key, 1, nx: true, ex: 1.day.to_i)

    lang = LANGS.include?(form[:lang].to_s) ? form[:lang].to_s : 'en'
    Tolzar::TrialMailer.confirmation(email, first_name(form[:name]), lang).deliver_later
  end

  def first_name(name)
    name.to_s.strip.split(/\s+/).first.to_s.gsub(/[^[:alpha:]'\-]/, '').first(40)
  end
end
