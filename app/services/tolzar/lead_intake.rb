# Tolzar lead intake (TikTok plan row 5, generic for any source): a lead form's answers posted to a workspace's
# lead URL become a contact on the first pipeline stage and a conversation with the answers, so the team (and the
# brain, in Shadow) can follow up. Sources: TikTok Instant Forms' CRM webhook, Meta lead ads through a connector,
# a website form, Zapier/Make. The URL is per API inbox and carries a secret derived from the app's key
# (Tolzar::WebhookToken), shown only to the workspace owner. TOLZAR_LEAD_INTAKE lists the workspace ids it runs
# for (comma-separated; empty = off). Nothing is sent to the lead from here.
class Tolzar::LeadIntake
  Refused = Class.new(StandardError)

  LABEL = 'lead'
  SOURCE = /\A[a-z0-9_-]{1,40}\z/
  EMAIL = /\A[^@\s]{1,64}@[^@\s]{1,190}\.[a-z]{2,24}\z/i
  MAX_ANSWERS = 40

  def self.accounts
    ENV.fetch('TOLZAR_LEAD_INTAKE', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def self.token(inbox)
    Tolzar::WebhookToken.derive('leads', inbox.id)
  end

  def self.url(inbox)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/tolzar/leads/#{inbox.id}/#{token(inbox)}"
  end

  # The lead inbox for a request, or nil (wrong token, not an API inbox, or the workspace not switched on).
  def self.inbox_for(inbox_id, given_token)
    inbox = Inbox.find_by(id: inbox_id, channel_type: 'Channel::Api')
    return unless inbox && accounts.include?(inbox.account_id)

    inbox if Tolzar::WebhookToken.match?(token(inbox), given_token)
  end

  def initialize(inbox:, params:)
    @inbox = inbox
    @account = inbox.account
    @params = params.to_h.with_indifferent_access
  end

  # => { conversation_id:, contact_id:, duplicate: }
  def perform
    raise Refused, 'no_contact' if email.blank? && raw_phone.blank? && name.blank?

    @inbox.with_lock do
      held = lead_id && @inbox.messages.find_by(source_id: "lead:#{lead_id}")
      next { conversation_id: held.conversation_id, contact_id: held.conversation.contact_id, duplicate: true } if held

      contact_inbox = contact_inbox_for(find_contact)
      tag_contact(contact_inbox.contact)
      conversation = create_conversation(contact_inbox)
      { conversation_id: conversation.id, contact_id: contact_inbox.contact_id, duplicate: false }
    end
  end

  private

  def email
    value = @params[:email].to_s.strip.downcase.first(255)
    value if value.match?(EMAIL)
  end

  # Only an international number (+…) goes on the contact (the contact model requires it); any other form stays
  # in the message text for the team.
  def phone
    value = raw_phone.gsub(/[^\d+]/, '')
    value if value.match?(/\A\+[1-9]\d{5,14}\z/)
  end

  def raw_phone
    @params[:phone].to_s.strip.first(30)
  end

  def name
    @params[:name].to_s.strip.first(120).presence || [@params[:first_name], @params[:last_name]].compact_blank.join(' ').first(120).presence
  end

  def source
    value = @params[:source].to_s.downcase.strip
    value.match?(SOURCE) ? value : 'form'
  end

  def lead_id
    @params[:lead_id].to_s.strip.first(120).presence
  end

  def detail(key)
    @params[key].to_s.strip.first(200).presence
  end

  # Answers as [question, answer] pairs: {"answers": {"q": "a"}} or [{"question"/"name": …, "answer"/"value": …}].
  def answers
    raw = @params[:answers] || @params[:fields]
    pairs = case raw
            when Hash then raw.to_a
            when Array then raw.filter_map { |a| [a['question'] || a['name'], a['answer'] || a['value']] if a.is_a?(Hash) }
            else []
            end
    pairs.first(MAX_ANSWERS).filter_map do |q, a|
      a = Array(a).join(', ') if a.is_a?(Array)
      [q.to_s.strip.first(200), a.to_s.strip.first(1000)] if q.present? && a.present?
    end
  end

  def find_contact
    (email && @account.contacts.find_by(email: email)) || (phone && @account.contacts.find_by(phone_number: phone))
  end

  def contact_inbox_for(contact)
    if contact
      ContactInbox.find_or_create_by!(contact: contact, inbox: @inbox) { |ci| ci.source_id = "lead:#{SecureRandom.uuid}" }
    else
      ContactInboxWithContactBuilder.new(
        inbox: @inbox, source_id: "lead:#{SecureRandom.uuid}",
        contact_attributes: { name: name || email || raw_phone, email: email, phone_number: phone }.compact
      ).perform
    end
  end

  # A new lead starts on the first stage; a contact already further along keeps its stage.
  def tag_contact(contact)
    attrs = (contact.custom_attributes || {}).dup
    stage_attr = Tolzar::PipelineSettings::STAGE_ATTRIBUTE
    attrs[stage_attr] = Tolzar::PipelineSettings.stage_keys(@account).first if attrs[stage_attr].blank?
    attrs['lead_source'] = source
    attrs['lead_id'] = lead_id if lead_id # the platform's own lead id (Tolzar::TiktokCrmEventJob sends it back)
    { 'lead_campaign' => :campaign, 'lead_ad' => :ad, 'lead_form' => :form }.each do |attr, key|
      attrs[attr] = detail(key) if detail(key)
    end
    contact.update!(custom_attributes: attrs)
  end

  def create_conversation(contact_inbox)
    conversation = Conversation.create!(
      account_id: @account.id, inbox_id: @inbox.id, contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id,
      additional_attributes: { 'tolzar_lead' => { 'source' => source, 'campaign' => detail(:campaign), 'ad' => detail(:ad),
                                                  'form' => detail(:form), 'lead_id' => lead_id }.compact }
    )
    conversation.messages.create!(account_id: @account.id, inbox_id: @inbox.id, message_type: :incoming,
                                  sender: contact_inbox.contact, content: message_text,
                                  source_id: lead_id ? "lead:#{lead_id}" : nil)
    conversation.update_labels([LABEL, "lead-#{source}"])
    conversation
  end

  def message_text
    head = ["New lead from #{source}", detail(:campaign) && "Campaign: #{detail(:campaign)}", detail(:ad) && "Ad: #{detail(:ad)}",
            detail(:form) && "Form: #{detail(:form)}"].compact
    contact = [name && "Name: #{name}", email && "E-mail: #{email}", raw_phone.presence && "Phone: #{raw_phone}"].compact
    [head.join("\n"), contact.join("\n"), answers.map { |q, a| "#{q}: #{a}" }.join("\n")].compact_blank.join("\n\n")
  end
end
