# Tolzar: what a Facebook / Instagram comment is about. Meta's comment webhook carries the post id
# but rarely its text, and never an Instagram caption or a picture, so staff (and later the AI) saw a
# comment like "how much?" with nothing to say what it was asked under. This job reads, with the
# page's own token (read-only):
#   - the post / ad / reel / story: text or caption, type, permalink and a picture, stored on the
#     conversation as additional_attributes.tolzar_comment.context. The picture is copied into our
#     storage, because Meta's picture links expire within days. One fetch per post (cached 12 h).
#   - for a reply: the comment it answers (text and author), on the message as
#     content_attributes.tolzar_comment_parent. A parent we already hold is read from our own copy.
# A post Meta will not show (deleted, or no permission) is stored as unavailable, with a link to try.
class Tolzar::MetaCommentContextJob < ApplicationJob
  queue_as :low

  TEXT_MAX = 1000
  THUMB_MAX_BYTES = 2.megabytes
  THUMB_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  CACHE_TTL = 12.hours
  FB_FIELDS = 'message,permalink_url,full_picture,status_type,created_time'.freeze
  IG_FIELDS = 'caption,permalink,media_type,media_product_type,thumbnail_url,media_url,timestamp'.freeze

  def perform(conversation_id, message_id = nil)
    @conversation = Conversation.find_by(id: conversation_id)
    return if @conversation.blank? || comment.blank? || channel.blank?

    message_id ? parent_for(@conversation.messages.find_by(id: message_id)) : post_context
  end

  private

  def comment
    @conversation.additional_attributes&.dig('tolzar_comment')
  end

  def channel
    @channel ||= @conversation.inbox.channel.then { |c| c if c.is_a?(Channel::FacebookPage) }
  end

  def instagram?
    comment['platform'] == 'instagram'
  end

  def post_context
    post_id = comment['post_id'].to_s
    return if post_id.blank? || comment['context'].present?

    context = Rails.cache.fetch("tolzar:meta_post:#{@conversation.inbox_id}:#{post_id}", expires_in: CACHE_TTL) { fetch_post(post_id) }
    attrs = @conversation.additional_attributes.deep_dup
    attrs['tolzar_comment'] = comment.merge('context' => context)
    @conversation.update!(additional_attributes: attrs)
  end

  def fetch_post(post_id)
    data = graph("/#{post_id}", instagram? ? IG_FIELDS : FB_FIELDS)
    instagram? ? instagram_context(data) : facebook_context(data, post_id)
  rescue Tolzar::MetaGraph::Error => e
    Rails.logger.info("[Tolzar comments] post context unavailable: inbox=#{@conversation.inbox_id} #{e.message.first(80)}")
    { 'unavailable' => true, 'permalink' => comment['permalink'] || fallback_link(post_id), 'fetched_at' => Time.current.iso8601 }
  end

  def facebook_context(data, post_id)
    {
      'type' => facebook_type(data['status_type']), 'text' => data['message'].to_s.first(TEXT_MAX).presence,
      'permalink' => data['permalink_url'].presence || fallback_link(post_id),
      'thumbnail_path' => copy_picture(data['full_picture']), 'posted_at' => data['created_time'],
      'fetched_at' => Time.current.iso8601
    }.compact
  end

  def instagram_context(data)
    picture = data['media_type'] == 'VIDEO' ? data['thumbnail_url'] : data['media_url']
    {
      'type' => instagram_type(data['media_product_type'], data['media_type']), 'text' => data['caption'].to_s.first(TEXT_MAX).presence,
      'permalink' => data['permalink'].presence, 'thumbnail_path' => copy_picture(picture),
      'posted_at' => data['timestamp'], 'fetched_at' => Time.current.iso8601
    }.compact
  end

  # post, photo, video, reel, story, ad (the card's label; anything else reads as a post).
  def facebook_type(status_type)
    case status_type.to_s
    when 'added_photos' then 'photo'
    when 'added_video' then 'video'
    else 'post'
    end
  end

  def instagram_type(product, media_type)
    case product.to_s
    when 'REELS' then 'reel'
    when 'STORY' then 'story'
    when 'AD' then 'ad'
    else media_type.to_s == 'VIDEO' ? 'video' : 'post'
    end
  end

  def fallback_link(post_id)
    instagram? ? nil : "https://www.facebook.com/#{post_id}"
  end

  # A small copy in our storage; the path stays valid when Meta's link expires. nil when it cannot be read.
  def copy_picture(url)
    return if url.blank?

    SafeFetch.fetch(url.to_s, max_bytes: THUMB_MAX_BYTES, allowed_content_type_prefixes: [], allowed_content_types: THUMB_TYPES) do |file|
      blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: "comment-post-#{@conversation.id}",
                                                    content_type: file.content_type)
      Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    end
  rescue SafeFetch::Error => e
    Rails.logger.info("[Tolzar comments] post picture not copied: #{e.class}")
    nil
  end

  def parent_for(message)
    parent_id = message&.content_attributes&.dig('tolzar_comment_parent_id').presence
    return if parent_id.blank? || message.content_attributes['tolzar_comment_parent'].present?

    message.update!(content_attributes: message.content_attributes.merge('tolzar_comment_parent' => parent_comment(parent_id)))
  end

  def parent_comment(parent_id)
    local = @conversation.inbox.messages.find_by(source_id: "comment:#{parent_id}")
    return { 'text' => local.content.to_s.first(TEXT_MAX), 'author' => local.sender&.name } if local

    data = graph("/#{parent_id}", instagram? ? 'text,username' : 'message,from')
    { 'text' => (data['text'] || data['message']).to_s.first(TEXT_MAX), 'author' => data['username'] || data.dig('from', 'name') }.compact
  rescue Tolzar::MetaGraph::Error
    { 'unavailable' => true }
  end

  def graph(path, fields)
    Tolzar::MetaGraph.get(path, { fields: fields }, channel.page_access_token, @conversation.account.tolzar_meta_app&.app_secret)
  end
end
