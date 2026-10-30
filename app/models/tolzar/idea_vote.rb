# Tolzar feature board: one user's vote on one idea (unique pair). shipped_notified_at records the "shipped"
# email, so a user is told once per idea even if the idea leaves shipped and comes back.
class Tolzar::IdeaVote < ApplicationRecord
  self.table_name = 'tolzar_idea_votes'

  belongs_to :idea, class_name: 'Tolzar::Idea', inverse_of: :votes, counter_cache: :votes_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :idea_id }

  # true when this process won the right to send the shipped email for this vote.
  def claim_ship_notice!
    self.class.where(id: id, shipped_notified_at: nil).update_all(shipped_notified_at: Time.current) == 1
  end

  def release_ship_notice!
    update_columns(shipped_notified_at: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
