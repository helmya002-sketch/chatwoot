# Tolzar feature board: a reply on an idea. Staff comments are written from the super admin page (a status
# change's explanation is one, pinned); a user's first post is held for review like a first idea.
class Tolzar::IdeaComment < ApplicationRecord
  include Tolzar::FeedbackModeration

  self.table_name = 'tolzar_idea_comments'

  BODY_MAX = 5_000

  belongs_to :idea, class_name: 'Tolzar::Idea', inverse_of: :comments
  belongs_to :user, optional: true

  validates :body, presence: true, length: { maximum: BODY_MAX }
end
