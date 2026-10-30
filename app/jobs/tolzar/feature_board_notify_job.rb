# Tolzar feature board emails, sent through the newsletter's own SMTP server (Tolzar::FeatureBoardMailer):
#   shipped  an idea moved to shipped: one email to each voter (the author's own vote is one), at most once per
#            idea and user (tolzar_idea_votes.shipped_notified_at), even if the idea is shipped again later
#   merged   a duplicate was merged: both authors are told where the votes went
# These are notices the user asked for by voting or posting, but they ride on the newsletter sender, so the
# newsletter's consent applies: a user who opted out of the newsletter, or whose address is suppressed (bounces,
# complaints), gets none of them. Off unless NEWSLETTER_ENABLED=true (the newsletter's switch): with the switch
# off the job does nothing, and votes stay unmarked.
class Tolzar::FeatureBoardNotifyJob < ApplicationJob
  queue_as :low

  def perform(kind, idea_id)
    return Rails.logger.info("[FeatureBoard] #{kind} notice for idea #{idea_id} not sent: NEWSLETTER_ENABLED is off") unless enabled?

    idea = Tolzar::Idea.find(idea_id)
    kind == 'shipped' ? notify_shipped(idea) : notify_merged(idea)
  end

  private

  def notify_shipped(idea)
    idea.votes.where(shipped_notified_at: nil).includes(:user).find_each do |vote|
      next if vote.user.nil? || blocked?(vote.user_id)
      next unless vote.claim_ship_notice!

      begin
        Tolzar::FeatureBoardMailer.shipped(idea, vote.user).deliver_now
      rescue StandardError
        vote.release_ship_notice! # not sent: the retry tries this user again
        raise
      end
    end
  end

  def notify_merged(duplicate)
    [duplicate.user, duplicate.merged_into.user].compact.uniq.each do |user|
      next if blocked?(user.id)

      Tolzar::FeatureBoardMailer.merged(duplicate, user).deliver_now
    end
  end

  def blocked?(user_id)
    Tolzar::NewsletterRecipient.blocked.exists?(user_id: user_id)
  end

  def enabled?
    Tolzar::NewsletterSendJob.enabled?
  end
end
