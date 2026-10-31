# Tolzar: a staff reply typed in a TikTok comment thread (Tolzar::TiktokCommentIngestService) goes out as a PUBLIC
# reply under the comment it answers, never as a DM. Only for TOLZAR_TIKTOK_COMMENT_REPLIES workspaces, only text
# (TikTok comments are text, 150 characters), and only from a person: an AI or bot message is never posted. Anything
# else stays in Tolzar, marked failed with the reason, so nothing is sent by surprise.
class Tolzar::TiktokCommentReply
  MAX_LENGTH = 150

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @channel = message.inbox.channel
  end

  def perform
    reason = refusal
    return fail!(reason) if reason

    new_id = client.reply(video_id, target_comment_id, text)
    @message.update!(source_id: ("comment:#{new_id}" if new_id.present?),
                     content_attributes: @message.content_attributes.merge('tolzar_comment_id' => new_id.presence,
                                                                           'tolzar_comment_parent_id' => target_comment_id).compact)
    Messages::StatusUpdateService.new(@message, 'delivered').perform
  rescue StandardError => e
    Rails.logger.error("[Tolzar] TikTok comment reply failed for message #{@message.id}: #{e.class}")
    fail!(e.message.to_s.first(200))
  end

  private

  def refusal
    return 'Replying to TikTok comments from Tolzar is not on for this workspace.' unless
      Tolzar::TiktokComments.replies_enabled?(@message.account_id)
    return 'Only a person can reply to a TikTok comment.' unless @message.sender.is_a?(User)
    return 'TikTok comment replies are text only.' if @message.attachments.any?
    return "TikTok comment replies are at most #{MAX_LENGTH} characters." if text.length > MAX_LENGTH
    return 'There is no comment to reply to in this thread.' if target_comment_id.blank? || video_id.blank?

    'The reply is empty.' if text.blank?
  end

  def text
    @text ||= @message.outgoing_content.to_s.strip
  end

  def video_id
    @conversation.additional_attributes.dig('tolzar_comment', 'post_id').to_s.presence
  end

  # The comment the reply quotes (in_reply_to), else the latest comment from the customer in the thread.
  def target_comment_id
    @target_comment_id ||= begin
      quoted = @message.content_attributes['in_reply_to'] && @conversation.messages.find_by(id: @message.content_attributes['in_reply_to'])
      quoted ||= @conversation.messages.incoming.where.not(source_id: nil).order(:created_at).last
      quoted&.content_attributes&.dig('tolzar_comment_id').to_s.presence
    end
  end

  def client
    Tolzar::TiktokComments::Client.new(business_id: @channel.business_id, access_token: @channel.validated_access_token)
  end

  def fail!(reason)
    Messages::StatusUpdateService.new(@message, 'failed', reason).perform
  end
end
