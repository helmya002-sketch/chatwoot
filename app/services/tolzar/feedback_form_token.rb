# Tolzar feature board: the signed time a post form was shown. A submit less than MIN_SECONDS later (a bot) or
# without a valid token is refused, together with the honeypot field (community plan §2: no CAPTCHA service).
module Tolzar::FeedbackFormToken
  PURPOSE = :tolzar_feedback_form
  MIN_SECONDS = 3
  TTL = 1.day

  def self.issue(now = Time.current)
    verifier.generate(now.to_i, purpose: PURPOSE, expires_in: TTL)
  end

  def self.human?(token, now = Time.current)
    shown_at = verifier.verified(token.to_s, purpose: PURPOSE)
    shown_at.is_a?(Integer) && now.to_i - shown_at >= MIN_SECONDS
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
