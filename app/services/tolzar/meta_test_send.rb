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
#   - one message: the window closes as it sends, success or not;
#   - every step (open, send, close) is written to the audit log; the message is saved in the
#     conversation, marked as the App Review test.
# It calls Meta directly (Tolzar::MetaGraph), so nothing else learns to send from a listen-only inbox.
class Tolzar::MetaTestSend
  KEY = 'tolzar_meta_test_send_until'
  WINDOW = 60.minutes
  MAX_TEXT = 300

  class Refused < StandardError; end

  def self.open_until(account)
    t = Time.zone.parse((account.settings || {})[KEY].to_s)
    t if t && t > Time.current
  rescue ArgumentError
    nil
  end

  def self.open!(account, user)
    until_at = Time.current + WINDOW
    account.update!(settings: (account.settings || {}).merge(KEY => until_at.iso8601))
    audit(account, user, 'open', until_at.iso8601)
    until_at
  end

  def self.close!(account, user, why)
    account.update!(settings: (account.settings || {}).except(KEY))
    audit(account, user, 'close', why)
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
    self.class.audit(@account, @user, 'sent', "conversation #{@conversation.display_id}")
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

    @checked = true
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
