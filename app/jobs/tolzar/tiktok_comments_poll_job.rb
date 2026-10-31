# Tolzar: reads new comments on the latest videos of every TikTok inbox in the TOLZAR_TIKTOK_COMMENTS workspaces
# (Tolzar::TiktokComments). Oldest first, so a reply lands after the comment it answers. One channel failing does not
# stop the others; nothing is ever posted to TikTok.
class Tolzar::TiktokCommentsPollJob < ApplicationJob
  queue_as :low

  def perform
    ids = Tolzar::TiktokComments.accounts
    return if ids.empty?

    Channel::Tiktok.where(account_id: ids).find_each do |channel|
      poll(channel)
    rescue StandardError => e
      Rails.logger.error("[Tolzar] TikTok comments poll failed for channel #{channel.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def poll(channel)
    client = Tolzar::TiktokComments::Client.new(business_id: channel.business_id, access_token: channel.validated_access_token)
    client.videos.each do |video|
      vid = (video['item_id'] || video['video_id']).to_s
      next if vid.blank?

      client.comments(vid).sort_by { |c| c['create_time'].to_i }.each do |comment|
        Tolzar::TiktokCommentIngestService.new(channel: channel, video: video, comment: comment).perform
      end
    end
  end
end
