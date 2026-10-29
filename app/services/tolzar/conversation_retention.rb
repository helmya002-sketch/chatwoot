# frozen_string_literal: true

# Tolzar: storage limitation for a workspace's own conversations (GDPR Art. 5(1)(e), Egypt PDPL),
# so what a business's privacy policy promises ("kept N months after your last message, then
# deleted") is what the system does. Per workspace, OFF unless the Owner sets a period: the account
# setting `tolzar_conversation_retention_days` (365 to 3650). Conversations whose last activity is
# older than that are destroyed with their messages and attachments; contacts left with no
# conversation are kept (a contact can be erased on request, Settings > A contact's data).
# The respond.io mirror inboxes are never touched (they are a read-only copy with their own rules).
class Tolzar::ConversationRetention
  KEY = 'tolzar_conversation_retention_days'
  MIN_DAYS = 365
  MAX_DAYS = 3650

  def self.days(account)
    value = (account.settings || {})[KEY]
    n = Integer(value, exception: false)
    n if n && n.between?(MIN_DAYS, MAX_DAYS)
  end

  # Every workspace with a period set; returns {account_id => deleted}.
  def self.purge_all(now: Time.current)
    Account.where("settings ->> '#{KEY}' IS NOT NULL").find_each.to_h { |account| [account.id, new(account, now: now).purge] }
  end

  def initialize(account, now: Time.current)
    @account = account
    @now = now
  end

  def expired
    days = self.class.days(@account)
    return Conversation.none if days.nil?

    mirror_ids = @account.inboxes.select { |i| Tolzar::MirrorConfig.mirror_inbox?(i) }.map(&:id)
    @account.conversations.where(last_activity_at: ...(@now - days.days)).where.not(inbox_id: mirror_ids)
  end

  def purge
    deleted = 0
    expired.find_in_batches(batch_size: 200) do |batch|
      Conversation.where(id: batch.map(&:id)).destroy_all
      deleted += batch.size
    end
    Rails.logger.info("[Tolzar retention] account=#{@account.id} period_days=#{self.class.days(@account)} deleted=#{deleted}")
    deleted
  end
end
