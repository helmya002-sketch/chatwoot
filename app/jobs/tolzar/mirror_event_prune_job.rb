# Tolzar: the raw respond.io webhook payloads of the shadow mirror (contact names, phones, e-mails,
# message text) are kept 180 days after they were projected, then emptied. The row itself stays (ids
# and times only) so a late redelivery is still recognised as a duplicate. Daily (config/schedule.yml).
class Tolzar::MirrorEventPruneJob < ApplicationJob
  queue_as :housekeeping

  KEEP = 180.days

  def perform(now: Time.current)
    emptied = Tolzar::MirrorEvent.where(processed_at: ...(now - KEEP)).where.not(payload: {})
                                 .in_batches(of: 1000).update_all(payload: {})
    Rails.logger.info("[Tolzar mirror prune] payloads_emptied=#{emptied}")
    emptied
  end
end
