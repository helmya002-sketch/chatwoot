# Tolzar ad-to-chat attribution (TikTok plan row 6; generic for any channel that tells us the ad): when the first
# message of a conversation came from an ad (click-to-message), the ad and campaign are kept on the conversation
# (additional_attributes.tolzar_ad) and, when the contact has none yet, on the contact (lead_source, lead_campaign,
# lead_ad), so the pipeline and Results show which ad brought the lead. Read tolerantly from the webhook payload
# (`referral`, `ad_info` or `ads_context`); confirm TikTok's field names on the first real ad click. Never sends.
module Tolzar::AdAttribution
  KEYS = %w[referral ad_info ads_context].freeze

  module_function

  def record(conversation:, contact:, payload:, platform:)
    ad = extract(payload)
    return if ad.blank? || conversation.additional_attributes&.key?('tolzar_ad')

    conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge(
      'tolzar_ad' => ad.merge('platform' => platform, 'at' => Time.current.utc.iso8601)
    ))
    tag_contact(contact, ad, platform)
  rescue StandardError => e
    Rails.logger.warn("[Tolzar] ad attribution skipped for conversation #{conversation&.id}: #{e.class}")
  end

  # {ad_id:, adgroup_id:, campaign_id:, ad_name:, campaign_name:} from the first referral-like block; nil without an ad.
  def extract(payload)
    data = (payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload.to_h).with_indifferent_access
    block = KEYS.lazy.map { |k| data[k] }.find { |v| v.is_a?(Hash) }
    return if block.blank?

    block = block.with_indifferent_access
    ad = { 'ad_id' => block[:ad_id], 'adgroup_id' => block[:adgroup_id] || block[:adset_id],
           'campaign_id' => block[:campaign_id], 'ad_name' => block[:ad_name] || block[:ad_title],
           'campaign_name' => block[:campaign_name] }.transform_values { |v| v.to_s.strip.first(200).presence }.compact
    ad if ad['ad_id'] || ad['campaign_id']
  end

  def tag_contact(contact, ad, platform)
    return if contact.blank?

    attrs = (contact.custom_attributes || {}).dup
    return if attrs['lead_source'].present?

    attrs['lead_source'] = "#{platform}_ad"
    attrs['lead_campaign'] = ad['campaign_name'] || ad['campaign_id'] if ad['campaign_name'] || ad['campaign_id']
    attrs['lead_ad'] = ad['ad_name'] || ad['ad_id'] if ad['ad_name'] || ad['ad_id']
    contact.update!(custom_attributes: attrs)
  end
end
