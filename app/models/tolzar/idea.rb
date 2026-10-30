# Tolzar feature board: one idea (#id) on the public board at /feedback (owner-approved community plan, 30 Oct
# 2026). Anyone reads; a signed-in user with a workspace posts, votes and comments. Every status change carries
# an explanation that becomes the pinned staff comment and a dated history row; moving to shipped emails the
# voters once (Tolzar::FeatureBoardNotifyJob). The author's own vote is added on posting, so "voters" includes
# the author. Generic: nothing here names a business.
class Tolzar::Idea < ApplicationRecord
  include Tolzar::FeedbackModeration

  self.table_name = 'tolzar_ideas'

  STATUSES = %w[under_review planned building shipped already_possible not_planned].freeze
  ROADMAP_STATUSES = %w[planned building shipped].freeze
  TAGS = %w[inbox channels ai_agents workflows contacts reports integrations other].freeze
  UI_LOCALES = %w[en ar de fr es pt].freeze # the board's pages and emails are translated into these
  TITLE_MAX = 140
  BODY_MAX = 5_000
  TRENDING_WINDOW = 7.days

  belongs_to :user, optional: true
  belongs_to :account, optional: true
  belongs_to :merged_into, class_name: 'Tolzar::Idea', optional: true, inverse_of: :duplicates
  belongs_to :changelog_entry, class_name: 'Tolzar::ChangelogEntry', optional: true, inverse_of: :ideas
  has_many :votes, class_name: 'Tolzar::IdeaVote', inverse_of: :idea, dependent: :delete_all
  has_many :comments, class_name: 'Tolzar::IdeaComment', inverse_of: :idea, dependent: :delete_all
  has_many :status_changes, class_name: 'Tolzar::IdeaStatusChange', inverse_of: :idea, dependent: :delete_all
  has_many :duplicates, class_name: 'Tolzar::Idea', foreign_key: :merged_into_id, inverse_of: :merged_into, dependent: :nullify

  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :body, presence: true, length: { maximum: BODY_MAX }
  validates :status, inclusion: { in: STATUSES }
  validates :tag, inclusion: { in: TAGS }, allow_nil: true
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }

  before_validation { self.tag = tag.presence }

  scope :on_board, -> { listed.where(merged_into_id: nil) }
  scope :top, -> { order(votes_count: :desc, id: :desc) }
  scope :newest, -> { order(created_at: :desc, id: :desc) }

  def self.filtered(status: nil, tag: nil, locale: nil, query: nil)
    scope = all
    scope = scope.where(status: status) if status
    scope = scope.where(tag: tag) if tag
    scope = scope.where(locale: locale) if locale
    scope = scope.where(arel_table[:title].matches("%#{sanitize_sql_like(query)}%")) if query.present?
    scope
  end

  # One page of a filtered scope: top (votes), new, or trending (most votes in the last 7 days first, then top).
  def self.page_of(scope, sort:, page:, per:)
    offset = (page - 1) * per
    case sort
    when 'new' then scope.newest.offset(offset).limit(per)
    when 'trending'
      ids = trending_ids(scope).slice(offset, per) || []
      scope.in_order_of(:id, ids)
    else scope.top.offset(offset).limit(per)
    end
  end

  def self.trending_ids(scope)
    recent = Tolzar::IdeaVote.where(idea_id: scope.select(:id), created_at: TRENDING_WINDOW.ago..).group(:idea_id).count
    rising = recent.sort_by { |id, count| [-count, -id] }.map(&:first)
    rising + scope.where.not(id: rising).top.pluck(:id)
  end

  # The spam rules let a user post links, and skip the review queue, once one of their posts was approved.
  def self.approved_author?(user)
    where(user_id: user.id, held: false, hidden: false).exists? ||
      Tolzar::IdeaComment.where(user_id: user.id, held: false, hidden: false, staff: false).exists?
  end

  # /feedback/<id>-<slug>; ASCII slug, so a title in a non-Latin script gives /feedback/<id>.
  def to_param
    slug = title.to_s.parameterize.first(80).delete_suffix('-')
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def pinned_comment
    comments.where(pinned: true, hidden: false).order(created_at: :desc).first
  end

  def comments_visible_to(viewer)
    visible = comments.listed
    visible = visible.or(comments.where(user_id: viewer.id, hidden: false)) if viewer
    visible.includes(:user).order(:created_at)
  end

  # A super admin moves the idea to another status. The explanation is required: it becomes the history row and
  # the pinned staff comment (the previous pinned one is unpinned and stays in the thread).
  def change_status!(to:, explanation:, by:)
    from = status
    transaction do
      status_changes.create!(from_status: from, to_status: to, explanation: explanation, changed_by_id: by.id)
      comments.where(pinned: true).update_all(pinned: false, updated_at: Time.current)
      comments.create!(user: by, body: explanation, staff: true, pinned: true)
      update!(status: to)
    end
    Tolzar::FeatureBoardNotifyJob.perform_later('shipped', id) if to == 'shipped' && from != 'shipped'
  end

  # Merge this duplicate into target: each voter's vote moves over unless they already voted there (one vote per
  # user stays true), both counters are recounted, and both authors are told by email.
  def merge_into!(target)
    transaction do
      votes.where(user_id: target.votes.select(:user_id)).delete_all
      votes.update_all(idea_id: target.id, updated_at: Time.current)
      update!(merged_into: target)
      self.class.reset_counters(id, :votes)
      self.class.reset_counters(target.id, :votes)
    end
    Tolzar::FeatureBoardNotifyJob.perform_later('merged', id)
  end
end
