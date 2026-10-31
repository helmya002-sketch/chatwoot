# Tolzar search within a contact (round 4, E5): finds words in one contact's messages (incoming, outgoing and private
# notes, since the viewer is staff), only in conversations the viewer may see (Conversations::PermissionFilterService,
# as Tolzar::ContactTimeline). Newest first, at most LIMIT; each hit carries a plain-text snippet around the match.
class Tolzar::ContactSearch
  LIMIT = 50
  SNIPPET = 160
  QUERY_LENGTH = (2..100)

  def self.valid_query?(query)
    QUERY_LENGTH.cover?(query.to_s.strip.length)
  end

  def initialize(account, contact, user, query)
    @account = account
    @contact = contact
    @user = user
    @query = query.to_s.strip
  end

  def results
    return [] if conversation_ids.empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    Message.where(account_id: @account.id, conversation_id: conversation_ids, message_type: %i[incoming outgoing])
           .where('messages.content ILIKE :pattern', pattern: pattern)
           .includes(:conversation).reorder(created_at: :desc).limit(LIMIT)
           .map { |m| { conversation_id: m.conversation.display_id, message_id: m.id, at: m.created_at.iso8601, snippet: snippet(m.content) } }
  end

  private

  def conversation_ids
    @conversation_ids ||= begin
      scope = @account.conversations.where(contact_id: @contact.id)
      Conversations::PermissionFilterService.new(scope, @user, @account).perform.reorder(nil).pluck(:id)
    end
  end

  # Plain text (tags removed, spaces squeezed), at most SNIPPET characters, centred on the first match.
  def snippet(content)
    text = ActionController::Base.helpers.strip_tags(content.to_s).squish
    return text if text.length <= SNIPPET

    at = text.downcase.index(@query.downcase) || 0
    start = (at - ((SNIPPET - @query.length) / 2)).clamp(0, text.length - SNIPPET)
    text[start, SNIPPET]
  end
end
