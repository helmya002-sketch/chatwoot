# frozen_string_literal: true

# Tolzar: storage limitation for a workspace's own conversations (GDPR Art. 5(1)(e), Egypt PDPL),
# so what a business's privacy policy promises ("kept N months after your last message, then
# deleted") is what the system does. Per workspace, OFF unless the Owner sets a period: the account
# setting `tolzar_conversation_retention_days` (365 to 3650). Conversations whose last activity is
# older than that are destroyed with their messages and attachments; contacts left with no
# conversation are kept (a contact can be erased on request, Settings > A contact's data).
# The brain is told which conversations went (POST /retention/forget), so it forgets their decisions,
# timers and per-conversation notes too. At most MAX_PER_RUN a night per workspace, so a big first
# run spreads over several nights instead of flooding Sidekiq. The respond.io mirror inboxes are never
# touched (they are a read-only copy with their own rules: Tolzar::MirrorEventPruneJob).
class Tolzar::ConversationRetention
  KEY = 'tolzar_conversation_retention_days'
  MIN_DAYS = 365
  MAX_DAYS = 3650
  MAX_PER_RUN = 2000

  def self.days(account)
    value = (account.settings || {})[KEY]
    n = Integer(value, exception: false)
    n if n && n.between?(MIN_DAYS, MAX_DAYS)
  end

  # Every workspace with a period set; returns {account_id => deleted}. One workspace failing does not
  # stop the others.
  def self.purge_all(now: Time.current)
    Account.where("settings ->> '#{KEY}' IS NOT NULL").find_each.to_h do |account|
      [account.id, new(account, now: now).purge]
    rescue StandardError => e
      Rails.logger.error("[Tolzar retention] account=#{account.id} failed: #{e.class}")
      [account.id, nil]
    end
  end

  def initialize(account, now: Time.current)
    @account = account
    @now = now
  end

  def expired
    days = self.class.days(@account)
    return Conversation.none if days.nil?

    cutoff = @now - days.days
    mirror_ids = @account.inboxes.select { |i| Tolzar::MirrorConfig.mirror_inbox?(i) }.map(&:id)
    @account.conversations.where(last_activity_at: ...cutoff).where.not(inbox_id: mirror_ids)
  end

  def purge
    deleted = 0
    expired.order(:id).limit(MAX_PER_RUN).in_batches(of: 200) do |relation|
      batch = relation.pluck(:id, :display_id)
      Conversation.where(id: batch.map(&:first)).destroy_all
      forget_in_brain(batch.map(&:last))
      deleted += batch.size
    end
    Rails.logger.info("[Tolzar retention] account=#{@account.id} period_days=#{self.class.days(@account)} deleted=#{deleted}")
    deleted
  end

  private

  # The brain keys conversations by their display id (Chatwoot's webhooks send it as the id).
  def forget_in_brain(display_ids)
    Tolzar::BrainClient.post('/retention/forget', { account_id: @account.id, conversation_ids: display_ids },
                             account_id: @account.id)
  rescue StandardError => e
    Rails.logger.warn("[Tolzar retention] account=#{@account.id} brain not told (#{e.class}); its own retention ages them out")
  end
end
