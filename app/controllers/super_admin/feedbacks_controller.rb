# Tolzar: the feature board's page in the super admin console (owner-approved community plan, 30 Oct 2026).
#   moderation queue  first posts held for review and reported posts: approve or hide
#   change status     with a required explanation: a dated history row plus the pinned staff comment; moving to
#                     shipped emails the voters (Tolzar::FeatureBoardNotifyJob, needs NEWSLETTER_ENABLED=true)
#   merge             a duplicate into another idea: votes carried over once per user, both authors told
#   changelog         write an entry (draft or published) and link the ideas it shipped
class SuperAdmin::FeedbacksController < SuperAdmin::ApplicationController
  def show
    @held_ideas = Tolzar::Idea.awaiting_moderation.includes(:user).order(:created_at).limit(50)
    @held_comments = Tolzar::IdeaComment.awaiting_moderation.includes(:user, :idea).order(:created_at).limit(50)
    @idea = Tolzar::Idea.find(params[:id]) if params[:id].present?
    @ideas = Tolzar::Idea.where(merged_into_id: nil, hidden: false, held: false).order(updated_at: :desc).limit(50)
    @entry = params[:entry_id].present? ? Tolzar::ChangelogEntry.find(params[:entry_id]) : Tolzar::ChangelogEntry.new
    @entries = Tolzar::ChangelogEntry.order(created_at: :desc).limit(20)
    @enabled = Tolzar::NewsletterSendJob.enabled?
  end

  def moderate
    record = (params[:kind] == 'comment' ? Tolzar::IdeaComment : Tolzar::Idea).find(params[:record_id])
    case params[:op]
    when 'approve' then record.approve!
    when 'hide' then record.hide!
    else return redirect_to(super_admin_feedback_path, alert: t('super_admin.feedback.invalid'))
    end
    log_action("#{params[:op]} #{params[:kind] == 'comment' ? 'comment' : 'idea'} #{record.id}")
    redirect_to super_admin_feedback_path, notice: t('super_admin.feedback.saved')
  end

  def change_status
    idea = Tolzar::Idea.find(params[:id])
    explanation = params[:explanation].to_s.strip
    unless params[:status].in?(Tolzar::Idea::STATUSES) && params[:status] != idea.status
      return redirect_to(super_admin_feedback_path(id: idea.id), alert: t('super_admin.feedback.invalid_status'))
    end
    return redirect_to(super_admin_feedback_path(id: idea.id), alert: t('super_admin.feedback.explanation_needed')) if explanation.blank?

    idea.change_status!(to: params[:status], explanation: explanation, by: current_super_admin)
    log_action("idea #{idea.id} -> #{params[:status]}")
    redirect_to super_admin_feedback_path(id: idea.id), notice: t('super_admin.feedback.saved')
  end

  def merge_idea
    idea = Tolzar::Idea.find(params[:id])
    target = Tolzar::Idea.find_by(id: params[:into_id].to_i)
    unless target && target.id != idea.id && target.merged_into_id.nil? && idea.merged_into_id.nil?
      return redirect_to(super_admin_feedback_path(id: idea.id), alert: t('super_admin.feedback.invalid_merge'))
    end

    idea.merge_into!(target)
    log_action("merged idea #{idea.id} into #{target.id}")
    redirect_to super_admin_feedback_path(id: target.id), notice: t('super_admin.feedback.merged')
  end

  def save_changelog
    entry = Tolzar::ChangelogEntry.find_by(id: params[:entry_id]) || Tolzar::ChangelogEntry.new(created_by_id: current_super_admin.id)
    entry.assign_attributes(params.require(:changelog_entry).permit(:title, :body_markdown))
    entry.published_at ||= Time.current if params[:publish] == '1'
    idea_ids = params[:idea_ids].to_s.scan(/\d+/).map(&:to_i)
    Tolzar::ChangelogEntry.transaction do
      entry.save!
      entry.ideas.where.not(id: idea_ids).update_all(changelog_entry_id: nil, updated_at: Time.current)
      Tolzar::Idea.where(id: idea_ids).update_all(changelog_entry_id: entry.id, updated_at: Time.current)
    end
    log_action("saved changelog entry #{entry.id}")
    redirect_to super_admin_feedback_path(entry_id: entry.id), notice: t('super_admin.feedback.saved')
  rescue ActiveRecord::RecordInvalid
    redirect_to super_admin_feedback_path(entry_id: entry.id), alert: entry.errors.full_messages.to_sentence
  end

  private

  def log_action(message)
    Rails.logger.info("[SuperAdmin] feedback #{message} (actor_id=#{current_super_admin.id})")
  end
end
