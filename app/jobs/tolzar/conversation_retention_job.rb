# Tolzar: daily, deletes conversations past each workspace's retention period (Tolzar::ConversationRetention).
# Only workspaces whose Owner set a period are touched.
class Tolzar::ConversationRetentionJob < ApplicationJob
  queue_as :housekeeping

  def perform
    Tolzar::ConversationRetention.purge_all
  end
end
