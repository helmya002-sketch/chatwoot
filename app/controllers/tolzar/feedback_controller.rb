# Tolzar: the public feature-request board, roadmap and changelog (owner-approved community plan, 30 Oct 2026).
#   GET  /feedback                     ideas: filters status/tag/language, sort top/new/trending, title search
#   POST /feedback                     post an idea
#   GET  /feedback/roadmap(.json)      planned / building / shipped with counts and definitions, no dates
#   GET  /feedback/changelog(.rss|.json)
#   GET  /feedback/:id-:slug           one idea: vote, comments, pinned staff explanation, dated status history
#   POST /feedback/:id/vote            vote or take the vote back
#   POST /feedback/:id/comments        comment
#   POST /feedback/:id/report          report an idea; POST /feedback/comments/:comment_id/report a comment
# Reading is public. Writing needs the dashboard login (the devise_token_auth cookie, checked server-side) and a
# workspace. Spam rules (plan §2): first post held for review, no links before an approved post, honeypot and a
# 3-second minimum, 5 posts and 30 votes per hour, shadow-hidden at 2 reports. Pages stay noindex until launch.
class Tolzar::FeedbackController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'tolzar_feedback'
  around_action :in_the_viewers_language
  before_action :require_member, only: [:create, :vote, :comment, :report, :report_comment]
  helper_method :viewer, :member?

  PER_PAGE = 50
  SORTS = %w[top new trending].freeze
  LINK = %r{https?://|www\.}i
  SHIPPED_ON_ROADMAP = 50
  JSON_MAX_AGE = 5.minutes

  def index
    @status = params[:status].presence_in(Tolzar::Idea::STATUSES)
    @tag = params[:tag].presence_in(Tolzar::Idea::TAGS)
    @language = params[:language].presence_in(I18n.available_locales.map(&:to_s))
    @sort = params[:sort].presence_in(SORTS) || 'top'
    @query = params[:q].to_s.strip.first(100)
    @page = [params[:page].to_i, 1].max
    scope = Tolzar::Idea.on_board.filtered(status: @status, tag: @tag, locale: @language, query: @query)
    @ideas = Tolzar::Idea.page_of(scope, sort: @sort, page: @page, per: PER_PAGE).to_a
    @status_counts = Tolzar::Idea.on_board.group(:status).count
    @languages = Tolzar::Idea.on_board.distinct.pluck(:locale).sort
    @voted_ids = viewer ? Tolzar::IdeaVote.where(user_id: viewer.id, idea_id: @ideas.map(&:id)).pluck(:idea_id) : []
    @form_token = Tolzar::FeedbackFormToken.issue
  end

  def roadmap
    @sections = Tolzar::Idea::ROADMAP_STATUSES.index_with do |status|
      scope = Tolzar::Idea.on_board.where(status: status)
      ideas = status == 'shipped' ? scope.order(updated_at: :desc).limit(SHIPPED_ON_ROADMAP) : scope.top
      { count: scope.count, ideas: ideas.to_a }
    end
    respond_to do |format|
      format.html
      format.json do
        public_json
        statuses = @sections.map do |status, section|
          { status: status, count: section[:count], ideas: section[:ideas].map { |idea| idea_json(idea) } }
        end
        render json: { statuses: statuses }
      end
    end
  end

  def changelog
    @entries = Tolzar::ChangelogEntry.published.includes(:ideas).limit(100).to_a
    respond_to do |format|
      format.html
      format.rss { render layout: false }
      format.json do
        public_json
        render json: { entries: @entries.map { |entry| changelog_json(entry) } }
      end
    end
  end

  def show
    @idea = Tolzar::Idea.find_by(id: params[:id].to_i)
    return render_error(:not_found, t('tolzar.feedback.errors.not_found')) unless @idea&.visible_to?(viewer)
    return redirect_to(tolzar_feedback_idea_path(@idea), status: :moved_permanently) if params[:id] != @idea.to_param

    @pinned = @idea.pinned_comment
    @comments = @idea.comments_visible_to(viewer).where.not(id: @pinned&.id).to_a
    @history = @idea.status_changes.order(:created_at).to_a
    @duplicates = @idea.duplicates.where(hidden: false).to_a
    @voted = viewer.present? && @idea.votes.exists?(user_id: viewer.id)
    @form_token = Tolzar::FeedbackFormToken.issue
  end

  def create
    attrs = params.require(:idea).permit(:title, :body, :tag, :locale)
    refusal = posting_refusal("#{attrs[:title]} #{attrs[:body]}")
    return render_error(*refusal) if refusal

    idea = Tolzar::Idea.new(attrs.merge(locale: attrs[:locale].presence || I18n.locale.to_s, user: viewer,
                                        account_id: viewer.account_users.order(:id).pick(:account_id), held: !approved_author?))
    Tolzar::Idea.transaction do
      idea.save!
      idea.votes.create!(user: viewer)
    end
    redirect_to tolzar_feedback_idea_path(idea), notice: t(idea.held ? 'tolzar.feedback.flash.held' : 'tolzar.feedback.flash.posted')
  rescue ActiveRecord::RecordInvalid
    render_error(:unprocessable_entity, idea.errors.full_messages.to_sentence)
  end

  def vote
    idea = Tolzar::Idea.on_board.find_by(id: params[:id].to_i)
    return render_error(:not_found, t('tolzar.feedback.errors.not_found')) if idea.nil?
    # The author's vote is their "notify me": it stays.
    return redirect_to(tolzar_feedback_idea_path(idea)) if idea.user_id == viewer.id
    return render_error(:too_many_requests, t('tolzar.feedback.errors.rate_limited')) if Tolzar::FeedbackRateLimit.exceeded?(:vote, viewer.id)

    existing = idea.votes.find_by(user_id: viewer.id)
    existing ? existing.destroy! : idea.votes.create!(user: viewer)
    redirect_back_or_to tolzar_feedback_idea_path(idea)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to tolzar_feedback_idea_path(idea)
  end

  def comment
    idea = Tolzar::Idea.find_by(id: params[:id].to_i)
    return render_error(:not_found, t('tolzar.feedback.errors.not_found')) unless idea&.visible_to?(viewer) && idea.merged_into_id.nil?

    body = params.require(:comment).permit(:body)[:body].to_s
    refusal = posting_refusal(body)
    return render_error(*refusal) if refusal

    comment = idea.comments.new(body: body, user: viewer, held: !approved_author?)
    return render_error(:unprocessable_entity, comment.errors.full_messages.to_sentence) unless comment.save

    redirect_to tolzar_feedback_idea_path(idea, anchor: "comment-#{comment.id}"),
                notice: t(comment.held ? 'tolzar.feedback.flash.held' : 'tolzar.feedback.flash.commented')
  end

  def report
    idea = Tolzar::Idea.find_by(id: params[:id].to_i)
    return render_error(:not_found, t('tolzar.feedback.errors.not_found')) unless idea&.visible_to?(viewer)

    idea.report!(viewer)
    redirect_to tolzar_feedback_path, notice: t('tolzar.feedback.flash.reported')
  end

  def report_comment
    comment = Tolzar::IdeaComment.find_by(id: params[:comment_id].to_i)
    return render_error(:not_found, t('tolzar.feedback.errors.not_found')) unless comment&.visible_to?(viewer) && comment.idea.visible_to?(viewer)

    comment.report!(viewer)
    redirect_to tolzar_feedback_idea_path(comment.idea), notice: t('tolzar.feedback.flash.reported')
  end

  private

  # The dashboard keeps its devise_token_auth credentials in this cookie (app/javascript/dashboard/api/auth.js);
  # checked here exactly as the forum's OAuth provider checks it.
  def viewer
    return @viewer if defined?(@viewer)

    @viewer = begin
      info = JSON.parse(cookies['cw_d_session_info'].to_s)
      user = User.find_by(uid: info['uid'].to_s)
      user if user&.valid_token?(info['access-token'].to_s, info['client'].to_s)
    rescue JSON::ParserError, TypeError
      nil
    end
  end

  # Tolzar users only: a confirmed user with at least one workspace (trial workspaces included).
  def member?
    viewer.present? && viewer.confirmed? && viewer.account_users.exists?
  end

  def require_member
    return render_error(:unauthorized, t('tolzar.feedback.errors.sign_in')) if viewer.nil?

    render_error(:forbidden, t('tolzar.feedback.errors.no_workspace')) unless member?
  end

  def approved_author?
    @approved_author = Tolzar::Idea.approved_author?(viewer) unless defined?(@approved_author)
    @approved_author
  end

  # The spam rules for an idea or a comment; nil when the post may go in.
  def posting_refusal(text)
    unless params[:website].blank? && Tolzar::FeedbackFormToken.human?(params[:form_token])
      return [:unprocessable_entity, t('tolzar.feedback.errors.too_fast')]
    end
    return [:too_many_requests, t('tolzar.feedback.errors.rate_limited')] if Tolzar::FeedbackRateLimit.exceeded?(:post, viewer.id)

    [:unprocessable_entity, t('tolzar.feedback.errors.no_links_yet')] if !approved_author? && LINK.match?(text)
  end

  def render_error(status, message)
    @message = message
    render :error, status: status
  end

  # The marketing site reads these: public data only (no names, no emails), cacheable for five minutes.
  def public_json
    expires_in JSON_MAX_AGE, public: true
    response.headers['Access-Control-Allow-Origin'] = '*'
  end

  def idea_json(idea)
    { id: idea.id, title: idea.title, votes: idea.votes_count, url: tolzar_feedback_idea_url(idea) }
  end

  def changelog_json(entry)
    { id: entry.id, title: entry.title, body_markdown: entry.body_markdown, published_at: entry.published_at.iso8601,
      url: tolzar_feedback_changelog_url(anchor: entry.anchor), ideas: entry.public_ideas.map { |i| idea_json(i) } }
  end

  def default_url_options
    { host: ENV.fetch('FRONTEND_URL') }
  end

  def in_the_viewers_language(&)
    I18n.with_locale(viewer_locale, &)
  end

  # The viewer's own Tolzar language when signed in, else the browser's, among the board's UI languages.
  def viewer_locale
    wanted = request.headers['Accept-Language'].to_s.split(',').map { |part| part.strip.first(2).downcase }
    wanted.unshift(Tolzar::NewsletterAudience.locale_for(viewer)) if viewer
    wanted.find { |locale| Tolzar::Idea::UI_LOCALES.include?(locale) } || 'en'
  end
end
