# Tolzar: delivery events from the newsletter's own MTA (Postal), PUBLIC because Postal calls it.
#   POST /tolzar/newsletter/postal/:webhook_token
# Two checks before anything is read: the path token (NEWSLETTER_WEBHOOK_TOKEN) and Postal's RSA-SHA256
# signature of the raw body (X-Postal-Signature-256, verified with the public key Postal shows for the server,
# NEWSLETTER_POSTAL_WEBHOOK_KEY). Unknown token = 404, bad signature = 403. The event is matched to our delivery
# by the Message-ID we set, so an event for any other mail is ignored.
class Tolzar::NewsletterPostalController < ActionController::API
  def create
    return head(:not_found) unless valid_path_token?

    raw = request.raw_post
    return head(:forbidden) unless valid_signature?(raw, request.headers['X-Postal-Signature-256'])

    Tolzar::NewsletterBounceService.new(JSON.parse(raw)).perform
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def valid_path_token?
    expected = ENV.fetch('NEWSLETTER_WEBHOOK_TOKEN', '')
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(params[:webhook_token].to_s, expected)
  end

  def valid_signature?(raw, signature)
    return false if signature.blank?

    key = ENV.fetch('NEWSLETTER_POSTAL_WEBHOOK_KEY')
    pem = key.include?('BEGIN PUBLIC KEY') ? key : "-----BEGIN PUBLIC KEY-----\n#{key.scan(/.{1,64}/).join("\n")}\n-----END PUBLIC KEY-----\n"
    OpenSSL::PKey::RSA.new(pem).verify(OpenSSL::Digest.new('SHA256'), Base64.decode64(signature), raw)
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    false
  end
end
