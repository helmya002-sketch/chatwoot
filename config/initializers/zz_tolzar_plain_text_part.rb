# Tolzar deliverability: every HTML-only mail also gets a text/plain part with the same content (Tolzar::PlainTextPart).
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(Tolzar::PlainTextPart)
  ActionMailer::Base.register_interceptor(Tolzar::MessageIdDomain) # FQDN Message-ID on the sender's domain (SRV-015)
end
