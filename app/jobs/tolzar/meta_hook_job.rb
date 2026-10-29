# Tolzar: the work behind one verified webhook body of a workspace's own Meta app. The controller only
# checks the signature and queues this, so Meta gets its 200 at once and does not redeliver.
class Tolzar::MetaHookJob < ApplicationJob
  queue_as :default

  def perform(meta_app_id, raw_body)
    app = Tolzar::MetaApp.find_by(id: meta_app_id)
    return if app.blank?

    Tolzar::MetaHookRouter.new(app, JSON.parse(raw_body)).perform
  rescue JSON::ParserError
    nil
  end
end
