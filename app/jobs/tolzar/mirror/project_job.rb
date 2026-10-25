# Tolzar shadow mirror: project a stored respond.io event into Chatwoot.
# Runs the real projector (P2); records any projection error on the row and
# still marks it processed so the queue drains (the raw payload is retained, so
# an errored event can be reprocessed later by clearing processed_at + error).
class Tolzar::Mirror::ProjectJob < ApplicationJob
  # :medium, not :low — Chatwoot works queues in strict priority order, so :low
  # starves behind the live instance's higher-queue jobs and the mirror lags.
  queue_as :medium

  def perform(event_id)
    event = Tolzar::MirrorEvent.find_by(id: event_id)
    return if event.nil? || event.processed_at.present?

    begin
      Tolzar::Mirror::Projector.new(event: event).call
      event.update!(processed_at: Time.current, error: nil)
    rescue StandardError => e
      Rails.logger.error("[tolzar-mirror] projection error event=#{event.id} #{e.class}: #{e.message}")
      event.update!(processed_at: Time.current, error: "#{e.class}: #{e.message}".first(480))
    end
  end
end
