# Tolzar deliverability (Server ops SRV-015, 31 Oct): a mail without its own Message-ID would get the Mail gem's
# default "<…@<container-hostname>.mail>", a non-FQDN that doesn't match the sending domain and that spam filters
# dislike. This interceptor gives such a mail "<uuid@<sender domain>>" (the domain of MAILER_SENDER_EMAIL, else
# of the From address). A Message-ID set by the mailer itself (conversation replies, for threading) is kept.
module Tolzar::MessageIdDomain
  module_function

  def delivering_email(message)
    return if message.message_id.present?

    domain = sender_domain(message)
    message.message_id = "<#{SecureRandom.uuid}@#{domain}>" if domain
  end

  def sender_domain(message)
    address = ENV['MAILER_SENDER_EMAIL'].to_s[/[^<\s@]+@([^>\s]+)/, 1] || Array(message.from).first.to_s.split('@', 2)[1]
    address.to_s.downcase.presence&.then { |d| d if d.include?('.') && !d.end_with?('.invalid', '.mail') }
  end
end
