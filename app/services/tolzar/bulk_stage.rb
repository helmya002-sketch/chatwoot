# Tolzar Pipeline: move the contacts of up to MAX_IDS conversations to one stage at once. The same change
# the board makes for one card (the contact's `lifecycle_stage`, merged into its custom attributes, other
# attributes untouched), for conversations the member may see (Conversations::PermissionFilterService),
# all or nothing in one transaction. Contacts are not audited by Chatwoot, so every changed contact gets
# its own audit row (old and new stage, who) in the workspace's audit log.
class Tolzar::BulkStage
  MAX_IDS = 200
  ATTRIBUTE = Tolzar::PipelineSettings::STAGE_ATTRIBUTE

  class Refused < StandardError
    attr_reader :ids

    def initialize(message, ids = [])
      super(message)
      @ids = ids
    end
  end

  def initialize(account:, user:, conversation_ids:, stage:)
    @account = account
    @user = user
    @ids = conversation_ids.uniq
    @stage = stage
  end

  # Returns the ids of the contacts whose stage changed (already in the stage: left alone).
  def perform
    conversations = Conversations::PermissionFilterService.new(@account.conversations.where(id: @ids), @user, @account).perform
    missing = @ids - conversations.pluck(:id)
    raise Refused.new('conversations_not_found', missing) if missing.any?

    Contact.transaction do
      @account.contacts.where(id: conversations.select(:contact_id)).order(:id).lock.filter_map { |contact| move(contact) }
    end
  end

  private

  def move(contact)
    old = contact.custom_attributes[ATTRIBUTE]
    return if old == @stage

    contact.update!(custom_attributes: contact.custom_attributes.merge(ATTRIBUTE => @stage))
    Audited::Audit.create!(auditable: contact, associated: @account, user: @user, action: 'update',
                           audited_changes: { ATTRIBUTE => [old, @stage] }, comment: 'Tolzar bulk stage')
    contact.id
  end
end
