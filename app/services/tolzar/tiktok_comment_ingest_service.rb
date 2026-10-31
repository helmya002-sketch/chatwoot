# frozen_string_literal: true

# Tolzar: one TikTok comment on the business's own video into the TikTok inbox (Tolzar::TiktokComments). One
# conversation per commenter per video, label `comment`, kept apart from DMs by its own contact-inbox source id.
# The business's own comments (staff replying in the TikTok app) become outgoing messages in the thread of the
# comment they answer. Idempotent on the comment id: a poll that sees the same comment again changes nothing.
class Tolzar::TiktokCommentIngestService
  LABEL = 'comment'

  def initialize(channel:, video:, comment:)
    @channel = channel
    @inbox = channel.inbox
    @video = video.to_h.with_indifferent_access
    @comment = comment.to_h.with_indifferent_access
  end

  def perform
    return if @inbox.blank? || comment_id.blank? || video_id.blank?

    @inbox.with_lock do
      next if existing_message

      from_business? ? staff_reply : customer_comment
    end
  end

  private

  def comment_id
    (@comment[:comment_id] || @comment[:id]).to_s.presence
  end

  def video_id
    (@video[:item_id] || @video[:video_id] || @comment[:video_id]).to_s.presence
  end

  def parent_id
    pid = (@comment[:parent_comment_id] || @comment[:reply_to_comment_id]).to_s
    pid.presence unless pid == '0'
  end

  def author_id
    (@comment[:user_id] || @comment[:open_id] || @comment[:unique_identifier]).to_s
  end

  def author_name
    (@comment[:display_name] || @comment[:username]).to_s.first(120).presence || 'TikTok user'
  end

  def text
    @comment[:text].to_s.first(5000)
  end

  def from_business?
    @comment[:owner] == true || (author_id.present? && author_id == @channel.business_id.to_s)
  end

  def customer_comment
    return if author_id.blank?

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: @inbox, source_id: "comment:tiktok:#{author_id}", contact_attributes: { name: author_name }
    ).perform
    conversation = thread_for(contact_inbox) || new_thread(contact_inbox)
    create_message(conversation, :incoming, contact_inbox.contact)
  end

  def staff_reply
    parent = parent_id && find_message(parent_id)
    return if parent.blank?

    create_message(parent.conversation, :outgoing, nil)
  end

  def thread_for(contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).find do |c|
      c.additional_attributes.dig('tolzar_comment', 'post_id') == video_id
    end
  end

  def new_thread(contact_inbox)
    conversation = Conversation.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: { 'tolzar_comment' => { 'platform' => 'tiktok', 'post_id' => video_id,
                                                     'first_comment_id' => comment_id,
                                                     'permalink' => @video[:share_url].to_s.first(500).presence,
                                                     'post_text' => @video[:caption].to_s.first(200).presence }.compact }
    )
    conversation.update_labels([LABEL])
    conversation
  end

  def create_message(conversation, type, sender)
    held = parent_id && find_message(parent_id)
    conversation.messages.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, message_type: type, sender: sender,
      content: text.presence || '(comment with no text)', source_id: "comment:#{comment_id}",
      content_attributes: { 'tolzar_comment_id' => comment_id, 'tolzar_comment_parent_id' => parent_id,
                            'in_reply_to' => (held.id if held&.conversation_id == conversation.id) }.compact
    )
  end

  def existing_message
    find_message(comment_id)
  end

  def find_message(id)
    @inbox.messages.find_by(source_id: "comment:#{id}")
  end
end
