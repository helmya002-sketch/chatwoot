# Tolzar: the website concierge (launch key `site-agent`; docs/reports/TOLZAR-LIVE-DEMO-PLAN-2026-10-31.md §5).
#   POST /tolzar/site/concierge           session, message (<= 500), lang, page, state (JSON string)
#                                          -> {reply, actions[], handoff, handoff_reason, turns_left}
#   POST /tolzar/site/concierge/handoff   session, optional email / name: the visitor agreed to talk to the team
# Answers come from the brain's concierge (brain concierge.py, on the demo account: no workspace touched). Actions are
# the brain's deterministic planner's, checked again here against the allowlist: nothing outside it reaches the
# browser, and no submit action exists. A hand-off the visitor agrees to becomes one normal conversation with the
# transcript in Tolzar's own contact inbox (TOLZAR_CONTACT_INBOX_ID, label site-concierge), once per session.
class Tolzar::SiteConciergeController < ActionController::Base
  include Tolzar::SiteDoor

  MAX_TURNS = 12
  MAX_MESSAGE = 500
  SLUG = /\A[a-z-]{2,40}\z/
  SCROLL_TARGETS = %w[pricing calculator demo faq trial compare plans].freeze
  CALCULATOR = { 'perDay' => 5..1000, 'mins' => 1..20, 'share' => 5..80 }.freeze
  PREFILL = { 'email' => 120, 'name' => 60, 'company' => 80, 'monthly' => 40, 'business_type' => 40 }.freeze
  CHANNELS = %w[whatsapp instagram messenger facebook telegram tiktok email webchat sms line viber].freeze
  EMAIL = /\A[^@\s]{1,64}@[^@\s]{1,190}\.[a-z]{2,24}\z/i

  def create
    return error(:bad_request, 'invalid') unless valid_request?

    wait = ip_wait
    return rate(wait) if wait

    history = transcript
    return rate(SESSION_TTL.to_i) if turns(history) >= MAX_TURNS

    res = Tolzar::BrainClient.post('/concierge/answer', { message: message, messages: history })
    answer(res, history + [{ 'role' => 'visitor', 'text' => message }])
  end

  def handoff
    return head(:not_found) if inbox.nil?
    return error(:bad_request, 'invalid') unless valid_session? && valid_email?

    history = transcript
    return error(:bad_request, 'invalid') if turns(history).zero?

    wait = ip_wait
    return rate(wait) if wait
    return render(json: { ok: true, duplicate: true }) unless first_handoff?

    create_conversation(history)
    render json: { ok: true }
  end

  private

  def door_prefix
    'tolzar:site_concierge'
  end

  def max_turns
    MAX_TURNS
  end

  def message
    @message ||= params[:message].to_s.strip
  end

  def valid_request?
    message.present? && message.length <= MAX_MESSAGE && valid_session? &&
      (params[:lang].blank? || params[:lang].to_s.match?(/\A[a-z]{2}(-[A-Za-z]{2})?\z/))
  end

  def valid_email?
    params[:email].blank? || params[:email].to_s.strip.match?(EMAIL)
  end

  def answer(res, messages)
    case res['status']
    when 200
      store(messages + [{ 'role' => 'ai', 'text' => res['reply'].to_s }])
      render json: view(res)
    when 429 then rate(SESSION_TTL.to_i)
    when 400 then error(:bad_request, 'invalid')
    when 404 then error(:not_found, 'off')
    else error(:service_unavailable, 'busy')
    end
  end

  def view(res)
    handoff = res['handoff'] == true
    actions = Array(res['actions']).filter_map { |a| clean_action(a) }
    actions << { type: 'handoff_human' } if handoff && inbox
    { reply: res['reply'].to_s, actions: actions.first(6), handoff: handoff,
      handoff_reason: res['handoff_reason'].presence, turns_left: [MAX_TURNS - turns(transcript), 0].max }
  end

  # The allowlist, value by value: anything else is dropped, never passed through.
  def clean_action(action)
    return unless action.is_a?(Hash)

    case action['type']
    when 'set_industry' then slug_action('set_industry', 'slug', action['slug'])
    when 'open_demo' then slug_action('open_demo', 'industry', action['industry'])
    when 'scroll_to' then { type: 'scroll_to', target: action['target'] } if SCROLL_TARGETS.include?(action['target'])
    when 'set_calculator' then calculator_action(action)
    when 'prefill_trial' then prefill_action(action['fields'])
    when 'open_booking' then { type: 'open_booking' }
    end
  end

  def slug_action(type, key, value)
    { type: type, key.to_sym => value } if value.is_a?(String) && value.match?(SLUG)
  end

  def calculator_action(action)
    values = CALCULATOR.filter_map do |key, range|
      [key.to_sym, action[key]] if action[key].is_a?(Integer) && range.cover?(action[key])
    end.to_h
    { type: 'set_calculator', **values } if values.any?
  end

  def prefill_action(fields)
    return unless fields.is_a?(Hash)

    clean = PREFILL.filter_map do |key, max|
      [key.to_sym, fields[key]] if fields[key].is_a?(String) && fields[key].length <= max
    end.to_h
    clean.delete(:email) unless clean[:email].to_s.match?(EMAIL)
    channels = Array(fields['channels']).select { |c| CHANNELS.include?(c) }.uniq
    clean[:channels] = channels if channels.any?
    { type: 'prefill_trial', fields: clean } if clean.any?
  end

  # One conversation per session: the flag lives as long as the session's turns.
  def first_handoff?
    Redis::Alfred.set(session_key('handoff'), '1', nx: true, ex: SESSION_TTL.to_i)
  end

  def inbox
    @inbox ||= Inbox.find_by(id: ENV.fetch('TOLZAR_CONTACT_INBOX_ID', nil).presence, channel_type: 'Channel::Api')
  end

  def create_conversation(history)
    email = params[:email].to_s.strip.downcase.presence
    name = params[:name].to_s.strip.first(60).presence
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox, source_id: SecureRandom.uuid,
      contact_attributes: { name: name || email || 'Website visitor', email: email }.compact
    ).perform
    conversation = Conversation.create!(account_id: inbox.account_id, inbox: inbox, contact: contact_inbox.contact,
                                        contact_inbox: contact_inbox,
                                        additional_attributes: { source: 'tolzar_site_concierge',
                                                                 page: params[:page].to_s.first(200).presence,
                                                                 lang: params[:lang].to_s.first(5).presence }.compact)
    conversation.messages.create!(account_id: inbox.account_id, inbox: inbox, message_type: :incoming,
                                  sender: contact_inbox.contact, content: transcript_text(history, email))
    conversation.add_labels(['site-concierge'])
  end

  def transcript_text(history, email)
    lines = history.map { |m| "#{m['role'] == 'visitor' ? 'Visitor' : 'Tolzar assistant'}: #{m['text']}" }
    lines << '' << '(No e-mail given: reply here or ask for one.)' unless email
    "Website concierge hand-off\n\n#{lines.join("\n")}"
  end
end
