# Tolzar: the signed per-user unsubscribe token in every newsletter. It never expires (an unsubscribe link must
# keep working in an old issue) and it can only opt that one user out of the newsletter, nothing else.
module Tolzar::NewsletterToken
  PURPOSE = :tolzar_newsletter_unsubscribe

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def self.for(user_id)
    verifier.generate(user_id, purpose: PURPOSE)
  end

  def self.user_id(token)
    verifier.verified(token.to_s, purpose: PURPOSE)
  end

  def self.unsubscribe_url(user_id)
    Rails.application.routes.url_helpers.tolzar_newsletter_unsubscribe_url(token: self.for(user_id),
                                                                          host: ENV.fetch('FRONTEND_URL'))
  end
end
