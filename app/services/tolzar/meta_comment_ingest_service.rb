# frozen_string_literal: true

# Tolzar: one Facebook Page or Instagram comment (a webhook `feed` / `comments` change) into the
# workspace's listen-only page inbox, so staff see it and the brain can draft a reply in Shadow like
# for any conversation. One conversation per commenter per post, kept apart from DMs (its own contact
# inbox source id, label `comment`). The page's own replies (staff answering in Business Suite) become
# outgoing messages in that thread. Edits update the message; removals add a note. Nothing is sent
# to Meta from here: replying to comments is a later, separately approved step.
class Tolzar::MetaCommentIngestService
  LABEL = 'comment'

  def initialize(channel:, platform:, value:)
    @channel = channel
    @inbox = channel.inbox
    @platform = platform
    @value = value.with_indifferent_access
  end

  def perform
    return if @inbox.blank? || comment_id.blank?
    return unless facebook_comment? || @platform == 'instagram'

    # One comment at a time per inbox: Meta redelivers when it does not get its 200 quickly, and two
    # deliveries of the same comment must not both insert.
    @inbox.with_lock do
      case verb
      when 'remove', 'hide' then removed
      when 'edited' then edited
      else added
      end
    end
  end

  private

  def facebook_comment?
    @platform == 'facebook' && @value[:item] == 'comment'
  end

  def verb
    @value[:verb].to_s
  end

  def comment_id
    (@value[:comment_id] || @value[:id]).to_s.presence
  end

  def post_id
    (@value[:post_id] || @value.dig(:media, :id)).to_s
  end

  def parent_id
    pid = @value[:parent_id].to_s
    pid.presence unless pid == post_id
  end

  def text
    (@value[:message] || @value[:text]).to_s.first(5000)
  end

  def author_id
    @value.dig(:from, :id).to_s
  end

  def author_name
    (@value.dig(:from, :name) || @value.dig(:from, :username)).to_s.first(120).presence || "#{@platform.capitalize} user"
  end

  # The page (or its Instagram account) wrote it: a staff reply.
  def from_business?
    author_id.present? && [@channel.page_id, @channel.instagram_id].compact.include?(author_id)
  end

  def added
    return if existing_message

    from_business? ? staff_reply : customer_comment
  end

  def customer_comment
    if author_id.blank?
      # Meta withholds the author for people who have not interacted with the app: say so in the log.
      Rails.logger.info("[Tolzar comments] no author from Meta, comment dropped: inbox=#{@inbox.id}")
      return
    end

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: @inbox, source_id: "comment:#{@platform}:#{author_id}", contact_attributes: { name: author_name }
    ).perform
    conversation = thread_for(contact_inbox) || new_thread(contact_inbox)
    message = create_message(conversation, :incoming, contact_inbox.contact)
    # The comment it answers, read after the commit (Tolzar::MetaCommentContextJob).
    return unless parent_id && message.content_attributes['in_reply_to'].blank?

    Tolzar::MetaCommentContextJob.set(wait: 2.seconds).perform_later(conversation.id, message.id)
  end

  # A reply by the page goes into the thread of the comment it answers; otherwise it is not ours to show.
  def staff_reply
    parent = parent_id && find_message(parent_id)
    return if parent.blank?

    create_message(parent.conversation, :outgoing, nil)
  end

  def thread_for(contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).find do |c|
      c.additional_attributes.dig('tolzar_comment', 'post_id') == post_id
    end
  end

  def new_thread(contact_inbox)
    conversation = Conversation.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: { 'tolzar_comment' => thread_attributes }
    )
    conversation.update_labels([LABEL])
    # What the comment is about (the post, ad, reel or story), fetched outside the webhook's lock.
    Tolzar::MetaCommentContextJob.set(wait: 2.seconds).perform_later(conversation.id)
    conversation
  end

  def thread_attributes
    { 'platform' => @platform, 'post_id' => post_id, 'first_comment_id' => comment_id,
      'permalink' => @value[:permalink_url].to_s.first(500).presence, 'post_text' => @value.dig(:post, :message).to_s.first(200).presence }
      .compact
  end

  # A reply to a comment we hold quotes it like any reply (in_reply_to); one we don't hold is read by
  # Tolzar::MetaCommentContextJob.
  def create_message(conversation, type, sender)
    held_parent = parent_id && find_message(parent_id)
    conversation.messages.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, message_type: type, sender: sender,
      content: text.presence || '(comment with no text)', source_id: "comment:#{comment_id}",
      content_attributes: { 'tolzar_comment_id' => comment_id, 'tolzar_comment_parent_id' => parent_id,
                            'in_reply_to' => held_parent&.id }.compact
    )
  end

  def edited
    message = existing_message
    return added if message.blank?

    message.update!(content: text.presence || message.content)
  end

  def removed
    message = existing_message
    return if message.blank? || find_message("#{comment_id}:removed")

    message.conversation.messages.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, message_type: :activity, source_id: "comment:#{comment_id}:removed",
      content: "Comment removed on #{@platform == 'instagram' ? 'Instagram' : 'Facebook'}"
    )
  end

  def existing_message
    find_message(comment_id)
  end

  def find_message(id)
    @inbox.messages.find_by(source_id: "comment:#{id}")
  end
end
