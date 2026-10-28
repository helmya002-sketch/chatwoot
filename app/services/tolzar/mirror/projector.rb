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
#               lifecycle, status, assignee:{id,firstName,lastName,email}, created_at }
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
    contact.additional_attributes = (contact.additional_attributes || {}).merge(rio_attrs(c)).merge(rio_channel_attrs)
    # The lifecycle also goes in custom_attributes: the contact filter (workflow triggers,
    # saved views) can query those, not additional_attributes.
    lifecycle = c['lifecycle'].presence
    contact.custom_attributes = (contact.custom_attributes || {}).merge('rio_lifecycle' => lifecycle) if lifecycle
    phone = c['phone'].to_s.strip
    contact.phone_number = phone if phone.start_with?('+')
    persist_contact(contact, phone)
    contact
  end

  def find_or_create_contact(rio_id, c)
    identifier = "rio:#{rio_id}"
    tries = 0
    begin
      existing = account.contacts.find_by(identifier: identifier)
      return existing if existing

      account.contacts.create!(identifier: identifier, name: contact_name(c, rio_id))
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # A concurrent job may have created it (DB unique race -> RecordNotUnique, or
      # the uniqueness VALIDATION fires first -> RecordInvalid). Re-find and reuse.
      found = account.contacts.find_by(identifier: identifier)
      return found if found

      tries += 1
      retry if tries < 3
      raise e
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
      # respond.io's lifecycle ("New Lead", "Customer Won", ...) is contact.lifecycle;
      # contact.status is the conversation state (open/closed). Until 28 Oct this read status.
      'rio_lifecycle' => c['lifecycle'].presence,
      'rio_status' => c['status']
    }.compact
  end

  # The respond.io channel the guest last wrote on (whatsapp_business, instagram, facebook,
  # other_email, ...). All mirror traffic shares one API inbox, so the Contacts page reads this
  # to show the real channel. Only set when the event carries a channel.
  def rio_channel_attrs
    source = payload.dig('channel', 'source').presence
    return {} if source.nil?

    { 'rio_channel_source' => source, 'rio_channel_name' => payload.dig('channel', 'name') }.compact
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
    content = message_content(inner)

    msg = conv.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: outgoing ? :outgoing : :incoming,
      content: content,
      sender: outgoing ? bootstrap.agent : contact,
      source_id: src,
      content_attributes: message_attributes(m, inner)
    )
    # Hand each customer turn to the Tolzar brain for read-only shadow evaluation.
    # Direct internal call (see BrainNotifyJob) — not a Chatwoot webhook, so it is
    # not blocked by Chatwoot's webhook SSRF guard. No-op unless TOLZAR_BRAIN_HOOK_URL
    # is set. Agent/outgoing turns are not sent: the brain reads the full thread at
    # triage time and only acts on a customer turn.
    Tolzar::Mirror::BrainNotifyJob.perform_later(msg.id) unless outgoing
  end

  ATTACHMENT_LABELS = { 'audio' => '[voice note]', 'image' => '[photo]', 'video' => '[video]', 'file' => '[file]' }.freeze

  # Voice notes / photos (roadmap: voice + image understanding): keep only the link and its
  # metadata, never the file. The brain fetches it into memory when that workspace turned the
  # feature on, keeps the transcript or the fields it read, and drops the bytes.
  def message_attributes(m, inner)
    attrs = m['timestamp'].present? ? { external_created_at: m['timestamp'] } : {}
    a = inner['attachment']
    return attrs unless inner['type'].to_s == 'attachment' && a.is_a?(Hash) && a['url'].present?

    attrs.merge(tolzar_attachment: {
                  type: a['type'].to_s, url: a['url'].to_s, mime: (a['mimeType'] || a['mime']).to_s,
                  size: a['size'].to_i, file_name: a['fileName'].to_s
                })
  end

  EMAIL_MAX_CHARS = 4000
  # The start of the quoted thread under a reply ("On Mon, X wrote:", "-----Original Message-----", "> ...").
  EMAIL_QUOTE = /^\s*(On .{0,200}wrote:|Am .{0,200}schrieb .{0,80}:|Le .{0,200}a écrit\s*:|-{2,}\s*Original Message\s*-{2,}|From:\s.+|>)/i

  # respond.io puts a WhatsApp/IG text in message.text, but an email's body in
  # message.message (plus message.subject): without them every email arrived as
  # "[email]" and the brain could only ask "which centre?" (28 Oct: 22 of 23 emails).
  def message_content(inner)
    return inner['text'] if inner['text'].present?
    if inner['type'].to_s == 'attachment'
      label = ATTACHMENT_LABELS[inner.dig('attachment', 'type').to_s] || '[attachment]'
      caption = inner.dig('attachment', 'description').presence
      return caption ? "#{label} #{caption}" : label
    end
    return "[#{inner['type'].presence || 'message'}]" unless inner['type'].to_s == 'email'

    body = inner['message'].to_s.gsub("\r\n", "\n")
    cut = body.index(EMAIL_QUOTE)
    body = body[0...cut] if cut&.positive?
    text = [inner['subject'].to_s.strip.presence&.then { |s| "Subject: #{s}" }, body.strip.presence].compact.join("\n\n")
    text.presence ? text[0, EMAIL_MAX_CHARS] : '[email]'
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
