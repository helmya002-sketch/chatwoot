# Tolzar shadow mirror: project a stored respond.io event into Tolzar.
# P1: ingest-only — just mark the event processed. P2 adds the real projector
# (upsert the mirror contact + conversation + message into the tenant's mirror inbox).
class Tolzar::Mirror::ProjectJob < ApplicationJob
  queue_as :low

  def perform(event_id)
    event = Tolzar::MirrorEvent.find_by(id: event_id)
    return if event.nil? || event.processed_at.present?

    # TODO(P2): Tolzar::Mirror::Projector.new(event).call
    event.update!(processed_at: Time.current)
  end
end
