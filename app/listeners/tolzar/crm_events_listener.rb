# Tolzar: a contact's pipeline stage changed (contact.updated) -> when the workspace links TikTok and the owner
# mapped that stage to an event, and the contact came from a TikTok lead (lead_source tiktok* with its lead id),
# send the event once (Tolzar::TiktokCrmEventJob). Everything else: nothing happens.
class Tolzar::CrmEventsListener < BaseListener
  include Singleton

  def contact_updated(event)
    contact = event.data[:contact]
    stage = new_stage(event.data[:changed_attributes])
    return if contact.blank? || stage.blank?

    attrs = contact.custom_attributes || {}
    return unless attrs['lead_source'].to_s.start_with?('tiktok') && attrs['lead_id'].present?

    link = Tolzar::AdPlatformLink.active_for(contact.account_id)
    name = link&.event_for(stage)
    Tolzar::TiktokCrmEventJob.perform_later(link.id, contact.id, name, stage) if name
  end

  private

  # The new lifecycle stage when custom_attributes changed it, else nil.
  def new_stage(changes)
    before, after = (changes || {}).with_indifferent_access['custom_attributes']
    attr = Tolzar::PipelineSettings::STAGE_ATTRIBUTE
    now = (after || {})[attr]
    now if now.present? && now != (before || {})[attr]
  end
end
