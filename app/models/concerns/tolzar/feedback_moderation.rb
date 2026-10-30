# Tolzar feature board: the moderation state an idea and a comment share (community plan §2, spam rules).
#   held           an account's first post, shown only to its author until a moderator approves it
#   hidden         a moderator hid it; nobody sees it on the board
#   reports_count  reports by distinct users (reporter_ids); at REPORTS_TO_HIDE it is shadow-hidden until a
#                  moderator approves (reports cleared) or hides it
module Tolzar::FeedbackModeration
  extend ActiveSupport::Concern

  REPORTS_TO_HIDE = 2

  included do
    scope :listed, -> { where(held: false, hidden: false, reports_count: ...REPORTS_TO_HIDE) }
    scope :awaiting_moderation, -> { where(hidden: false, held: true).or(where(hidden: false, reports_count: 1..)) }
  end

  # What the board shows this viewer: the public posts, plus the viewer's own post while it waits for review.
  def visible_to?(viewer)
    return false if hidden
    return true unless held || reports_count >= REPORTS_TO_HIDE

    viewer.present? && user_id == viewer.id
  end

  def approve!
    update!(held: false, hidden: false, reports_count: 0, reporter_ids: [])
  end

  def hide!
    update!(hidden: true)
  end

  # One report per user; an author cannot report their own post. true when the report was counted.
  def report!(reporter)
    with_lock do
      next false if user_id == reporter.id || reporter_ids.include?(reporter.id)

      update!(reporter_ids: reporter_ids + [reporter.id], reports_count: reports_count + 1)
    end
  end
end
