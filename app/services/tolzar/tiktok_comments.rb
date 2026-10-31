# Tolzar TikTok plan row 2 (TOLZAR-LAUNCH-CHANNELS-PLAN §5): comments on the business's own TikTok videos become
# inbox conversations, like Meta comments (Tolzar::MetaCommentIngestService): one conversation per commenter per
# video, label `comment`, the video's caption and link as context, the brain drafts in Shadow. READ-ONLY toward
# TikTok: nothing is posted; replying to comments from Tolzar is a later step behind its own go.
# TOLZAR_TIKTOK_COMMENTS: the workspace ids it runs for (comma-separated; empty = off). Polled every 15 minutes.
# API (TikTok API for Business, Accounts): GET business/video/list/ and business/comment/list/. Field names follow
# TikTok's docs and are read tolerantly; confirm them on the first real run after the app's approval.
module Tolzar::TiktokComments
  VIDEOS_PER_RUN = 10
  COMMENTS_PER_VIDEO = 50

  module_function

  def accounts
    ENV.fetch('TOLZAR_TIKTOK_COMMENTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def enabled?(account_id)
    accounts.include?(account_id.to_i)
  end

  # Thin client for the two read endpoints (the upstream Tiktok::Client covers DMs only).
  class Client
    pattr_initialize [:business_id!, :access_token!]

    def videos(limit: VIDEOS_PER_RUN)
      fields = %w[item_id caption create_time thumbnail_url share_url]
      data = get('business/video/list/', business_id: business_id, fields: fields.to_s, max_count: limit)
      Array(data['videos'] || data['list']).first(limit)
    end

    def comments(video_id, limit: COMMENTS_PER_VIDEO)
      data = get('business/comment/list/', business_id: business_id, video_id: video_id, max_count: limit,
                                           sort_field: 'create_time', sort_order: 'desc')
      Array(data['comments'] || data['list']).first(limit)
    end

    private

    def get(path, query)
      response = HTTParty.get("#{base_url}/#{path}", query: query, headers: { 'Access-Token': access_token }, timeout: 15)
      raise "TikTok #{path}: HTTP #{response.code}" unless response.success?

      json = JSON.parse(response.body)
      raise "TikTok #{path}: #{json['code']} #{json['message']}" unless json['code'].to_i.zero?

      json['data'] || {}
    end

    def base_url
      "https://business-api.tiktok.com/open_api/#{GlobalConfigService.load('TIKTOK_API_VERSION', 'v1.3')}"
    end
  end
end
