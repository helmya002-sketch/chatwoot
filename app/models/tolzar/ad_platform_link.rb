# Tolzar ad-platform link (TikTok plan row 7): when a contact that came from a TikTok lead reaches a pipeline stage
# the owner mapped to an event (stage_events, e.g. {"Customer Won" => "CompletePayment"}), Tolzar sends that event
# to the workspace's TikTok event set (Tolzar::TiktokCrmEventJob). Off unless the workspace is in
# TOLZAR_TIKTOK_CRM_EVENTS AND the owner turned the link on; nothing is mapped by default. Token encrypted, write-only.
class Tolzar::AdPlatformLink < ApplicationRecord
  self.table_name = 'tolzar_ad_platform_links'

  PLATFORMS = %w[tiktok].freeze
  EVENT_NAME = /\A[A-Za-z][A-Za-z0-9_]{1,40}\z/

  belongs_to :account
  encrypts :token

  validates :platform, inclusion: { in: PLATFORMS }
  validates :event_set_id, format: { with: /\A[A-Za-z0-9_-]{4,64}\z/ }, if: :enabled
  validates :token, presence: true, if: :enabled
  validate :stage_events_shape

  def self.allowed?(account_id)
    ENV.fetch('TOLZAR_TIKTOK_CRM_EVENTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def self.active_for(account_id, platform = 'tiktok')
    return unless allowed?(account_id)

    find_by(account_id: account_id, platform: platform, enabled: true)
  end

  def event_for(stage)
    stage_events[stage.to_s].presence
  end

  def view
    { platform: platform, enabled: enabled, event_set_id: event_set_id, token: token.present? ? 'set' : 'not set',
      stage_events: stage_events, sent_count: sent_count, last_sent_at: last_sent_at, last_error: last_error }
  end

  private

  def stage_events_shape
    return errors.add(:stage_events, 'must be a map of stage to event') unless stage_events.is_a?(Hash)

    stages = Tolzar::PipelineSettings.stage_keys(account)
    stage_events.each do |stage, event|
      errors.add(:stage_events, "unknown stage #{stage}") unless stages.include?(stage)
      errors.add(:stage_events, "event name #{event} is not valid") unless event.to_s.match?(EVENT_NAME)
    end
  end
end
