# Tolzar feature board: one dated step of an idea's status history, with the explanation shown to everyone.
class Tolzar::IdeaStatusChange < ApplicationRecord
  self.table_name = 'tolzar_idea_status_changes'

  belongs_to :idea, class_name: 'Tolzar::Idea', inverse_of: :status_changes
  belongs_to :changed_by, class_name: 'User', optional: true

  validates :to_status, inclusion: { in: Tolzar::Idea::STATUSES }
  validates :explanation, presence: true, length: { maximum: Tolzar::IdeaComment::BODY_MAX }
end
