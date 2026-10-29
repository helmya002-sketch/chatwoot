# frozen_string_literal: true

class Integrations::Facebook::MessageParser
  # Tolzar: the referral fields kept (short plain values only, like the WhatsApp path keeps no ad
  # text or media URLs). The brain's links.ref_of reads `ref`.
  REFERRAL_KEYS = %w[source type ref].freeze
  REFERRAL_MAX = 64

  def initialize(response_json)
    @response = JSON.parse(response_json)
    @messaging = @response['messaging'] || @response['standby']
  end

  def sender_id
    @messaging.dig('sender', 'id')
  end

  def recipient_id
    @messaging.dig('recipient', 'id')
  end

  def time_stamp
    @messaging['timestamp']
  end

  def content
    # Messenger postbacks arrive outside the `message` payload, so we fall back
    # to the visible title first and then to the raw payload identifier.
    @messaging.dig('message', 'text') || postback_title || postback_payload
  end

  def sequence
    @messaging.dig('message', 'seq')
  end

  def attachments
    @messaging.dig('message', 'attachments')
  end

  def identifier
    @messaging.dig('message', 'mid') || @messaging.dig('postback', 'mid')
  end

  def postback_title
    @messaging.dig('postback', 'title')
  end

  def postback_payload
    @messaging.dig('postback', 'payload')
  end

  def delivery
    @messaging['delivery']
  end

  def read
    @messaging['read']
  end

  def read_watermark
    read&.dig('watermark')
  end

  def delivery_watermark
    delivery&.dig('watermark')
  end

  def echo?
    @messaging.dig('message', 'is_echo')
  end

  def app_id
    @messaging.dig('message', 'app_id')
  end

  def sent_from_chatwoot_app?
    app_id.present? && app_id.to_s == GlobalConfigService.load('FB_APP_ID', '').to_s
  end

  def in_reply_to_external_id
    @messaging.dig('message', 'reply_to', 'mid')
  end

  # Messenger's referral: a standalone `referral` event, or one inside a postback (Get Started on
  # an m.me ref link) or a message (an ad). Nil unless it is a Hash.
  def referral
    ref = @messaging['referral'] || @messaging.dig('postback', 'referral') || @messaging.dig('message', 'referral')
    ref.is_a?(Hash) ? ref : nil
  end

  # {'source', 'type', 'ref'} as short plain strings, only when the referral carries a `ref`.
  def referral_attributes
    ref = referral
    return if ref.nil?

    out = REFERRAL_KEYS.each_with_object({}) do |key, attrs|
      value = ref[key]
      next unless value.is_a?(String) || value.is_a?(Integer)

      value = value.to_s.strip[0, REFERRAL_MAX]
      attrs[key] = value if value.present?
    end
    out['ref'].present? ? out : nil
  end

  # A referral event on its own: nothing to show as a message.
  def standalone_referral?
    @messaging['referral'].is_a?(Hash) && @messaging['message'].blank? && @messaging['postback'].blank?
  end
end

# Sample Response
# {
#   "sender":{
#     "id":"USER_ID"
#   },
#   "recipient":{
#     "id":"PAGE_ID"
#   },
#   "timestamp":1458692752478,
#   "message":{
#     "mid":"mid.1457764197618:41d102a3e1ae206a38",
#     "seq":73,
#     "text":"hello, world!",
#     "quick_reply": {
#       "payload": "DEVELOPER_DEFINED_PAYLOAD"
#     }
#   }
# }
