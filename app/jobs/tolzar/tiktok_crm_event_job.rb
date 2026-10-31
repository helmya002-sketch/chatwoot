# Tolzar: one CRM event to TikTok's Events API (event_source crm, the workspace's event set), for a contact that
# came from a TikTok lead. Sent once per contact and event (a Redis key for 400 days). Only the lead id, the event
# name and its time leave Tolzar: no name, e-mail, phone or message content.
class Tolzar::TiktokCrmEventJob < ApplicationJob
  queue_as :low
  ENDPOINT = 'https://business-api.tiktok.com/open_api/v1.3/event/track/'.freeze

  def perform(link_id, contact_id, event_name, stage)
    link = Tolzar::AdPlatformLink.find_by(id: link_id, enabled: true)
    contact = Contact.find_by(id: contact_id)
    return unless link && contact && Tolzar::AdPlatformLink.allowed?(link.account_id)

    lead_id = contact.custom_attributes&.dig('lead_id').to_s
    return if lead_id.blank?

    key = "tolzar:tiktok_crm:#{link.id}:#{contact.id}:#{event_name}"
    return if Redis::Alfred.exists?(key)

    send_event(link, lead_id, event_name, stage)
    Redis::Alfred.set(key, '1', ex: 400.days.to_i)
    link.update!(sent_count: link.sent_count + 1, last_sent_at: Time.current, last_error: nil)
  rescue StandardError => e
    link&.update_columns(last_error: e.message.to_s.first(200)) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn("[Tolzar] TikTok CRM event not sent for contact #{contact_id}: #{e.class}")
  end

  private

  def send_event(link, lead_id, event_name, stage)
    body = { event_source: 'crm', event_source_id: link.event_set_id,
             data: [{ event: event_name, event_time: Time.current.to_i,
                      lead: { lead_id: lead_id, lead_event_source: 'tolzar' }, properties: { stage: stage.to_s.first(60) } }] }
    SafeFetch.fetch(ENDPOINT, method: :post, body: body.to_json, open_timeout: 10, read_timeout: 10,
                              headers: { 'Access-Token' => link.token, 'Content-Type' => 'application/json' },
                              sensitive_headers: ['Access-Token'], validate_content_type: false) do |result|
      json = JSON.parse(result.tempfile.read)
      raise "TikTok: #{json['code']} #{json['message']}" unless json['code'].to_i.zero?
    end
  end
end
