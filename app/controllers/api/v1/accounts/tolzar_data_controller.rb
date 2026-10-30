# Tolzar data deletion (queue item C; what the site and the trial terms promise), Owner-only:
#   POST tolzar/data/contact_erase  {contact_id, confirm}       one person: the brain's rows (DSAR delete), then
#                                                               the Chatwoot contact with its conversations,
#                                                               messages and attachments. confirm = the contact's
#                                                               name or e-mail, typed.
#   POST tolzar/data/workspace_purge {confirm, dry_run}        the whole workspace (Tolzar::WorkspacePurge).
#                                                               dry_run (default) counts; a real purge needs the
#                                                               workspace name typed and cannot be undone.
class Api::V1::Accounts::TolzarDataController < Api::V1::Accounts::TolzarController
  before_action :ensure_owner

  def contact_erase
    contact = Current.account.contacts.find_by(id: params[:contact_id].to_i)
    return render(json: { ok: false, error: 'contact_not_found' }, status: :not_found) if contact.nil?
    return render(json: { ok: false, error: 'confirm_mismatch' }, status: :unprocessable_entity) unless confirmed?(contact)

    brain = post_to_brain('/dsar/delete', { account_id: account_scope_id, contact_id: contact.id })
    # 404 = the brain holds nothing for this contact; anything else that is not ok stops before Chatwoot.
    unless brain.is_a?(Hash) && (brain['ok'] == true || brain['detail'].to_s.include?('not in this workspace'))
      return render(json: { ok: false, error: 'brain_refused', detail: brain.is_a?(Hash) ? brain['detail'] : nil }, status: :bad_gateway)
    end

    counts = { conversations: contact.conversations.count, messages: Message.where(sender: contact).count }
    contact.destroy!
    Rails.logger.warn("[Tolzar] contact erased account=#{Current.account.id} contact=#{contact.id} by user #{Current.user.id}")
    render json: { ok: true, brain: brain['deleted'] || {}, chatwoot: counts }
  end

  def workspace_purge
    dry_run = params[:dry_run].to_s != 'false'
    if !dry_run && params[:confirm].to_s.strip != Current.account.name
      return render json: { ok: false, error: 'confirm_mismatch' }, status: :unprocessable_entity
    end

    render json: { ok: true }.merge(Tolzar::WorkspacePurge.new(account: Current.account, actor: Current.user, dry_run: dry_run).perform)
  rescue Tolzar::WorkspacePurge::Refused => e
    render json: { ok: false, error: 'brain_refused', detail: e.message }, status: :bad_gateway
  end

  private

  def confirmed?(contact)
    typed = params[:confirm].to_s.strip.downcase
    typed.present? && [contact.name, contact.email].compact.map { |v| v.to_s.strip.downcase }.include?(typed)
  end
end
