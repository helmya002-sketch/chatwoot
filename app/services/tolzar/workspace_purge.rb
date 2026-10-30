# Tolzar: remove a whole workspace (queue item C; billing v1's end of the 30-day data hold). First the
# brain's rows (POST /workspace/purge, which only touches this workspace), then the Chatwoot side through
# DeleteObjectJob (contacts, conversations, messages, attachments, inboxes, then the account itself).
# dry_run (the default) only counts. A real purge is irreversible: callers are the Owner with a typed
# confirmation (TolzarDataController) or the billing purge job after the hold, and both are logged.
class Tolzar::WorkspacePurge
  class Refused < StandardError; end

  def initialize(account:, actor: nil, dry_run: true)
    @account = account
    @actor = actor
    @dry_run = dry_run
  end

  def perform
    brain = Tolzar::BrainClient.post('/workspace/purge', { account_id: @account.id, confirm: "purge-#{@account.id}",
                                                           dry_run: @dry_run }, account_id: @account.id)
    raise Refused, brain_error(brain) unless brain.is_a?(Hash) && brain['ok'] == true

    chatwoot = { contacts: @account.contacts.count, conversations: @account.conversations.count, inboxes: @account.inboxes.count }
    unless @dry_run
      Rails.logger.warn("[Tolzar] workspace #{@account.id} purge started by #{@actor ? "user #{@actor.id}" : 'billing hold'}: " \
                        "brain=#{brain['deleted'].to_json} chatwoot=#{chatwoot.to_json}")
      Tolzar::Subscription.find_by(account_id: @account.id)&.update!(purged_at: Time.current)
      DeleteObjectJob.perform_later(@account, @actor)
    end
    { dry_run: @dry_run, brain: brain['would_delete'] || brain['deleted'] || {}, chatwoot: chatwoot }
  end

  private

  def brain_error(res)
    res.is_a?(Hash) ? (res['detail'] || res['error'] || 'brain_refused').to_s.first(200) : 'brain_unreachable'
  end
end
