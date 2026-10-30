# frozen_string_literal: true

# Tolzar: the ONE message a listen-only Facebook Page / Instagram inbox may send, for Meta's App Review
# screencast (Meta wants to see a message sent by the app). Owner rule: only to the Owner's own
# account, never to a customer; the listen-only guard stays on for every other send.
#
# How narrow it is:
#   - off unless the Owner opens a window (account setting KEY, an expiry time, at most WINDOW);
#   - only a conversation in this workspace's listen-only page inbox, whose contact carries the
#     Owner's own name and wrote in the last 24 hours (Meta's reply window);
#   - the Owner types that name again to confirm;
#   - Facebook Messenger: Meta itself confirms the sender holds a role on the app (ID matching
#     against the app's roles); a name alone can be copied. Anything Meta does not confirm is refused;
#   - Instagram DM: Meta offers no role confirmation for an Instagram-scoped id (ID matching is
#     Messenger-only, and /{app}/roles lists Facebook users only, with no Instagram id). So, for
#     Instagram ONLY, opening the window issues a one-time code (CODE_SIZE characters, SecureRandom,
#     valid CODE_TTL or until the window closes) shown to the Owner in the panel; the Owner sends it
#     by Instagram DM from their own account, and the test reply is allowed only in a conversation
#     with an incoming message, written after the code was issued, that is exactly that code. This
#     proves whoever controls the sending Instagram account also holds the Owner's Tolzar session.
#     WEAKER than a role confirmation (it does not prove an app role). Only an HMAC of the code is
#     stored (account settings are audited); every other check still applies;
#   - one message: the window closes as it sends, success or not;
#   - every step (open, send, close) is written to the audit log; the message is saved in the
#     conversation, marked as the App Review test.
# It calls Meta directly (Tolzar::MetaGraph), so nothing else learns to send from a listen-only inbox.
class Tolzar::MetaTestSend
  KEY = 'tolzar_meta_test_send_until'
  WINDOW = 60.minutes
  MAX_TEXT = 300
  CODE_KEY = 'tolzar_meta_test_send_code'
  CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
  CODE_SIZE = 6
  CODE_TTL = 10.minutes

  class Refused < StandardError; end

  def self.open_until(account)
    t = Time.zone.parse((account.settings || {})[KEY].to_s)
    t if t && t > Time.current
  rescue ArgumentError
    nil
  end

  # Returns the window's end and the one-time Instagram code (shown once, to the Owner).
  def self.open!(account, user)
    until_at = Time.current + WINDOW
    code = Array.new(CODE_SIZE) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join
    digest = code_digest(account, code)
    entry = { 'digest' => digest, 'issued_at' => Time.current.iso8601(6), 'expires_at' => (Time.current + CODE_TTL).iso8601(6) }
    account.update!(settings: (account.settings || {}).merge(KEY => until_at.iso8601, CODE_KEY => entry))
    audit(account, user, 'open', until_at.iso8601)
    audit(account, user, 'code issued', "hmac #{digest.first(12)}")
    { until: until_at, code: code }
  end

  def self.close!(account, user, why)
    account.update!(settings: (account.settings || {}).except(KEY, CODE_KEY))
    audit(account, user, 'close', why)
  end

  # Keyed with the server's secret, so the digest in settings and audits cannot be brute-forced.
  def self.code_digest(account, code)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "#{CODE_KEY}:#{account.id}:#{code.to_s.strip.upcase}")
  end

  def self.audit(account, user, step, detail)
    Audited::Audit.create!(auditable: account, associated: account, user: user, action: 'update',
                           audited_changes: { 'tolzar_meta_test_send' => [step, detail.to_s.first(200)] },
                           comment: 'Tolzar App Review test send')
  end

  def initialize(account:, user:, conversation_id:, text:, confirm_name:)
    @account = account
    @user = user
    @conversation = account.conversations.find_by(display_id: conversation_id.to_i)
    @text = text.to_s.strip
    @confirm = confirm_name.to_s.strip
  end

  def perform
    check!
    channel = @conversation.inbox.channel
    app = @account.tolzar_meta_app
    psid = @conversation.contact_inbox.source_id
    res = Tolzar::MetaGraph.send_test_message(psid, @text, channel.page_access_token, app.app_secret)
    message = @conversation.messages.create!(
      account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing, sender: @user,
      content: @text, source_id: res['message_id'].presence || "tolzar-test-#{SecureRandom.hex(6)}",
      content_attributes: { 'tolzar_app_review_test' => true }
    )
    detail = "conversation #{@conversation.display_id}"
    detail += ' (Instagram, one-time code matched)' if instagram?
    self.class.audit(@account, @user, 'sent', detail)
    message
  ensure
    self.class.close!(@account, @user, 'used') if @checked
  end

  private

  def check!
    raise Refused, 'Open the test-send window first (60 minutes, one message)' unless self.class.open_until(@account)
    raise Refused, 'Conversation not found in this workspace' if @conversation.nil?
    raise Refused, 'Only a listen-only Facebook Page / Instagram inbox' unless listen_only_page?
    raise Refused, 'Text: 1 to 300 characters' unless @text.length.between?(1, MAX_TEXT)

    name = @conversation.contact&.name.to_s.strip
    raise Refused, "Only to your own account: the contact must be named #{@user.name}" unless same_name?(name, @user.name)
    raise Refused, 'Type the contact name exactly to confirm' unless same_name?(@confirm, name)
    raise Refused, 'Write to the Page from your account first (Meta allows replies within 24 hours)' unless recent_incoming?
    if instagram?
      raise Refused, 'Instagram: send the one-time code by DM from your own account first (valid 10 minutes)' unless code_received?
    else
      raise Refused, 'Meta does not confirm this sender has a role on the app (admin, developer, tester)' unless role_holder?
    end

    @checked = true
  end

  def instagram?
    @conversation.additional_attributes&.dig('type') == 'instagram_direct_message'
  end

  # Instagram only (see the header): an incoming message in THIS conversation, written after the code
  # was issued and before it expired, that is exactly the code (trimmed, any case). The window's close
  # clears the code, so it works once.
  def code_received?
    entry = (@account.settings || {})[CODE_KEY]
    return false unless entry.is_a?(Hash) && Time.zone.parse(entry['expires_at'].to_s)&.future?

    issued_at = Time.zone.parse(entry['issued_at'].to_s)
    @conversation.messages.incoming.where(created_at: issued_at..).pluck(:content).any? do |content|
      ActiveSupport::SecurityUtils.secure_compare(self.class.code_digest(@account, content), entry['digest'].to_s)
    end
  rescue ArgumentError
    false
  end

  # The platform check (a name can be copied): Meta must confirm the sender holds a role on the app.
  def role_holder?
    Tolzar::MetaGraph.app_role_holder?(@account.tolzar_meta_app, @conversation.contact_inbox.source_id,
                                       @conversation.inbox.channel.page_access_token)
  rescue Tolzar::MetaGraph::Error
    false
  end

  def listen_only_page?
    channel = @conversation.inbox.channel
    channel.is_a?(Channel::FacebookPage) && Tolzar::ListenOnly.channel?(channel)
  end

  def same_name?(left, right)
    left.present? && left.casecmp?(right.to_s.strip)
  end

  def recent_incoming?
    @conversation.messages.incoming.where(created_at: 24.hours.ago..).exists?
  end
end
