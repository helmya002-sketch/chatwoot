# Tolzar proxy helpers the dashboard pages used to work around: one team summary for the Dashboard
# (instead of one conversations/meta request per team), moving many pipeline cards at once, and an AI
# agent's saved versions and copies. Same doors as TolzarController (brain client, roles, account scope).
class Api::V1::Accounts::TolzarHelpersController < Api::V1::Accounts::TolzarController
  # The Dashboard and the Pipeline are open to every member; each sees only the conversations they may
  # see (Conversations::PermissionFilterService). Agent versions stay administrator-only (ensure_admin);
  # a duplicate creates an agent, so it is Owner-only like every agent save.
  skip_before_action :ensure_admin, only: %i[team_summary bulk_stage]
  before_action :ensure_owner, only: :agent_duplicate
  before_action :ensure_agent_id, only: %i[agent_versions agent_duplicate]

  # Waiting follows the workspace SLA the brain keeps (Settings > SLA); no SLA config (brain down) = no SLA on.
  def team_summary
    sla = get_from_brain("/sla?account_id=#{account_scope_id}")['config']
    render json: { ok: true }.merge(Tolzar::TeamSummary.new(account: Current.account, user: Current.user, sla: sla).perform)
  end

  def bulk_stage
    ids = params[:conversation_ids]
    stage = params[:stage]
    unless ids.is_a?(Array) && ids.size.between?(1, Tolzar::BulkStage::MAX_IDS) && ids.all?(Integer)
      return invalid_params("conversation_ids: 1 to #{Tolzar::BulkStage::MAX_IDS} conversation ids")
    end
    return invalid_params('stage: one of the workspace pipeline stages') unless Tolzar::PipelineSettings.stage_keys(Current.account).include?(stage)

    changed = Tolzar::BulkStage.new(account: Current.account, user: Current.user, conversation_ids: ids, stage: stage).perform
    render json: { ok: true, stage: stage, updated: changed.size, contact_ids: changed }
  rescue Tolzar::BulkStage::Refused => e
    render json: { ok: false, error: e.message, conversation_ids: e.ids }, status: :not_found
  end

  def agent_versions
    versions = Tolzar::AgentVersion.for_agent(Current.account, params[:agent_id].to_s).newest_first
                                   .limit(Tolzar::AgentVersion::KEEP).includes(:saved_by)
    render json: { ok: true, agent_id: params[:agent_id].to_s, versions: versions.map(&:view) }
  end

  # A copy of the agent as the brain has it now: a new id, " (copy)" after the name, inactive (the
  # Owner turns it on), saved through the same brain path as the builder's Save (and versioned too).
  def agent_duplicate
    listing = get_from_brain("/agents?account_id=#{account_scope_id}")
    return render_brain(listing) if listing['error'].present?

    source = Array(listing['agents']).find { |agent| agent.is_a?(Hash) && agent['id'].to_s == params[:agent_id].to_s }
    return render(json: { ok: false, error: 'agent_not_found' }, status: :not_found) if source.nil?

    copy = source.merge('id' => "a#{SecureRandom.alphanumeric(7).downcase}", 'name' => "#{source['name']} (copy)", 'status' => 'inactive')
    saved = post_to_brain('/agents', { account_id: account_scope_id, agent: copy })
    record_agent_version(saved)
    render_brain saved
  end

  private

  def ensure_agent_id
    head(:not_found) unless params[:agent_id].to_s.match?(AGENT_ID)
  end

  def invalid_params(detail)
    render json: { ok: false, error: 'invalid_params', detail: detail }, status: :unprocessable_entity
  end
end
