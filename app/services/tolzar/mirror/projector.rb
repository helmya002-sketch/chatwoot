# Tolzar shadow mirror: project one stored respond.io event into Chatwoot as a
# real (read-only) conversation/contact/message in the tenant's mirror inbox.
#
# Everything is idempotent (keyed on respond.io ids) and SAFE: messages land in
# an API mirror inbox tagged tolzar_mirror, so SendReplyJob hard-skips them and
# nothing is ever delivered to a customer. Real emails are never written to the
# contact record (kept only in additional_attributes).
#
# respond.io payload shape (from respond.io's own webhook samples):
#   contact:  { id, firstName, lastName, phone, email, countryCode, language,
#               status, assignee:{id,firstName,lastName,email}, created_at }
#   message:  { messageId, channelMessageId, contactId, channelId,
#               traffic:"incoming"|"outgoing", message:{type,text,...}, timestamp }
#   channel:  { id, name, source:"whatsapp"|"email"|... }
class Tolzar::Mirror::Projector
  pattr_initialize [:event!]

  def call
    return if payload.blank?

    t = event.event_type.to_s
    if t =~ /message\.(received|sent)/i
      project_message
    elsif t.match?(/assignee/i)
      project_assignee
    elsif t.match?(/closed/i)
      project_closed
    elsif t.match?(/lifecycle/i)
      touch_contact
    elsif t.match?(/comment/i)
      project_comment
    elsif contact_payload['id'].present?
      touch_contact
    end
  end

  private

  def payload
    @payload ||= event.payload || {}
  end

  def contact_payload
    payload['contact'] || {}
  end

  def tenant
    event.tenant
  end

  def bootstrap
    @bootstrap ||= Tolzar::Mirror::Bootstrap.new(tenant: tenant)
  end

  def account
    bootstrap.account
  end

  def inbox
    bootstrap.inbox
  end

  # ---- entity upserts ---------------------------------------------------------

  def upsert_contact(c = contact_payload)
    rio_id = c['id']
    return nil if rio_id.blank?

    contact = find_or_create_contact(rio_id, c)
    contact.name = contact_name(c, rio_id)
    contact.additional_attributes = (contact.additional_attributes || {}).merge(rio_attrs(c))
    phone = c['phone'].to_s.strip
    contact.phone_number = phone if phone.start_with?('+')
    persist_contact(contact, phone)
    contact
  end

  def find_or_create_contact(rio_id, c)
    tries = 0
    begin
      account.contacts.find_or_create_by!(identifier: "rio:#{rio_id}") { |ct| ct.name = contact_name(c, rio_id) }
    rescue ActiveRecord::RecordNotUnique
      tries += 1
      retry if tries < 3 # lost the create race; retry will find the existing row
      raise
    end
  end

  def contact_name(c, rio_id)
    [c['firstName'], c['lastName']].compact.join(' ').strip.presence || "Contact #{rio_id}"
  end

  def rio_attrs(c)
    {
      'rio_id' => c['id'],
      'rio_email' => c['email'],        # kept here, NEVER on contact.email (leak guard)
      'country_code' => c['countryCode'],
      'language' => c['language'],
      'rio_lifecycle' => c['status']
    }
  end

  def persist_contact(contact, phone)
    contact.save!
  rescue ActiveRecord::RecordInvalid
    # phone/format rejected — keep the raw phone in attributes, save without it
    contact.phone_number = nil
    contact.additional_attributes = (contact.additional_attributes || {}).merge('rio_phone' => phone)
    contact.save!
  end

  def contact_inbox_for(contact)
    rio_id = contact.additional_attributes['rio_id']
    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: "rio:#{rio_id}").perform
  end

  def conversation_for(contact_inbox)
    contact_inbox.conversations.order(created_at: :desc).first ||
      ConversationBuilder.new(
        params: ActionController::Parameters.new(
          additional_attributes: { 'rio_channel_source' => payload.dig('channel', 'source') }
        ),
        contact_inbox: contact_inbox
      ).perform
  end

  # ---- per-event projections --------------------------------------------------

  def touch_contact
    upsert_contact
  end

  def project_message
    contact = upsert_contact
    return if contact.nil?

    ci = contact_inbox_for(contact)
    return if ci.nil?

    conv = conversation_for(ci)
    m = payload['message'] || {}
    src = "rio:msg:#{m['messageId']}"
    return if m['messageId'].blank? || conv.messages.exists?(source_id: src)

    outgoing = m['traffic'].to_s == 'outgoing'
    inner = m['message'] || {}
    content = inner['text'].presence || "[#{inner['type'].presence || 'message'}]"

    conv.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: outgoing ? :outgoing : :incoming,
      content: content,
      sender: outgoing ? bootstrap.agent : contact,
      source_id: src,
      content_attributes: m['timestamp'].present? ? { external_created_at: m['timestamp'] } : {}
    )
  end

  def project_assignee
    contact = upsert_contact
    return if contact.nil?

    ci = contact_inbox_for(contact)
    conv = ci&.conversations&.order(created_at: :desc)&.first
    return if conv.nil?

    a = contact_payload['assignee']
    if a.is_a?(Hash) && a['id'].present?
      name = [a['firstName'], a['lastName']].compact.join(' ').strip.presence || "Agent #{a['id']}"
      conv.update!(assignee: bootstrap.agent_for(name, "u#{a['id']}"))
    else
      conv.update!(assignee: nil)
    end
  end

  def project_closed
    rio_id = contact_payload['id']
    return if rio_id.blank?

    contact = account.contacts.find_by(identifier: "rio:#{rio_id}")
    return if contact.nil?

    conv = inbox.conversations.where(contact_id: contact.id).order(created_at: :desc).first
    conv.resolved! if conv && !conv.resolved?
  end

  def project_comment
    contact = upsert_contact
    return if contact.nil?

    ci = contact_inbox_for(contact)
    return if ci.nil?

    conv = conversation_for(ci)
    cm = payload['comment'] || payload['note'] || {}
    text = (cm['text'] || cm['comment'] || cm['body']).to_s
    text = '[comment]' if text.blank?
    src = "rio:cmt:#{cm['id'] || event.event_id}"
    return if conv.messages.exists?(source_id: src)

    conv.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      private: true,
      content: text,
      sender: bootstrap.agent,
      source_id: src
    )
  end
end
