# Tolzar feature board: one changelog entry (/feedback/changelog, its RSS and JSON). Linked both ways with the
# ideas it shipped: each idea points at its entry (tolzar_ideas.changelog_entry_id). A draft has no published_at.
class Tolzar::ChangelogEntry < ApplicationRecord
  self.table_name = 'tolzar_changelog_entries'

  TITLE_MAX = 200
  BODY_MAX = 50_000

  has_many :ideas, class_name: 'Tolzar::Idea', inverse_of: :changelog_entry, dependent: :nullify

  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :body_markdown, presence: true, length: { maximum: BODY_MAX }

  scope :published, -> { where(published_at: ..Time.current).order(published_at: :desc, id: :desc) }

  # Markdown to HTML; raw HTML in the body is not rendered (CommonMarker's default), the views sanitize again.
  def body_html
    CommonMarker.render_html(body_markdown.to_s, [:DEFAULT], [:table, :strikethrough, :autolink])
  end

  # The linked ideas the public may see (a moderator can hide a linked idea later).
  def public_ideas
    ideas.reject { |idea| idea.hidden || idea.held }
  end

  def anchor
    "entry-#{id}"
  end
end
