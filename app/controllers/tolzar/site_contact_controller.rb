# Tolzar: the marketing site's trial / contact form (owner's ask via the Oracle, 30 Oct 2026).
#   POST /tolzar/site/contact   name, email (required), company, company_url, industry, volume, phone, topic, lang,
#                               message; `website` is the honeypot. Topics: trial demo contact pricing partner setup
#                               calculator other (anything else = contact); each conversation gets the label site-<topic>.
#                               A trial request also sends the requester the trial confirmation mail (Tolzar::TrialMail).
# Each request lands as a new conversation in one API inbox of Tolzar's own workspace (TOLZAR_CONTACT_INBOX_ID),
# from a contact found or created by email, so trial requests are answered in Tolzar like any other chat.
# No login, no CSRF token (a static site posts it): the honeypot answers "thanks" and stores nothing, and each IP
# may send PER_IP_HOUR forms an hour (plus a GLOBAL_DAY cap for the whole form). A plain HTML form gets a 303 to
# the thank-you page of the site it came from (an allowed origin from Origin or Referer, + /thanks/ or
# /<lang>/thanks/), else to TOLZAR_CONTACT_REDIRECT; fetch() gets JSON, with CORS only for TOLZAR_CONTACT_ORIGINS.
# Unset TOLZAR_CONTACT_INBOX_ID turns the endpoint off (404).
class Tolzar::SiteContactController < ActionController::Base
  skip_forgery_protection
  before_action :set_cors_headers
  before_action :require_inbox, only: :create

  PER_IP_HOUR = 5
  GLOBAL_DAY = 300
  TOPICS = %w[trial demo contact pricing partner setup calculator other].freeze
  LIMITS = { name: 100, email: 255, company: 150, company_url: 255, industry: 80, volume: 40, phone: 40, lang: 10,
             message: 2000 }.freeze
  EMAIL = URI::MailTo::EMAIL_REGEXP

  def create
    return respond_ok if params[:website].present?
    return respond_error(:too_many_requests, 'rate_limited') if rate_limited?

    form = cleaned_form
    return respond_error(:unprocessable_entity, 'invalid_email') unless form[:email].match?(EMAIL)

    create_conversation(form)
    Tolzar::TrialMail.deliver_later(form) if form[:topic] == 'trial'
    respond_ok
  end

  # CORS preflight for fetch() with a JSON body.
  def preflight
    head(allowed_origin ? :no_content : :forbidden)
  end

  private

  def inbox
    @inbox ||= Inbox.find_by(id: ENV.fetch('TOLZAR_CONTACT_INBOX_ID', nil).presence, channel_type: 'Channel::Api')
  end

  def require_inbox
    head :not_found if inbox.nil?
  end

  def cleaned_form
    form = LIMITS.to_h { |key, max| [key, params[key].to_s.strip.first(max)] }
    form[:email] = form[:email].downcase
    form[:topic] = params[:topic].to_s.presence_in(TOPICS) || 'contact'
    form
  end

  def create_conversation(form)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: SecureRandom.uuid,
      contact_attributes: { name: form[:name].presence || form[:email], email: form[:email],
                            additional_attributes: { company_name: form[:company].presence }.compact }
    ).perform
    conversation = Conversation.create!(account_id: inbox.account_id, inbox: inbox, contact: contact_inbox.contact,
                                        contact_inbox: contact_inbox,
                                        additional_attributes: { source: 'tolzar_site_form', topic: form[:topic],
                                                                 lang: form[:lang].presence }.compact)
    conversation.messages.create!(account_id: inbox.account_id, inbox: inbox, message_type: :incoming,
                                  sender: contact_inbox.contact, content: message_text(form))
    conversation.add_labels(["site-#{form[:topic]}"]) # the team filters "Book a setup call", calculator results, …
  end

  def message_text(form)
    lines = ["Website form: #{form[:topic]}"]
    lines << "Name: #{form[:name]}" if form[:name].present?
    lines << "Email: #{form[:email]}"
    lines << "Company: #{form[:company]}" if form[:company].present?
    lines << "Website: #{form[:company_url]}" if form[:company_url].present?
    lines << "Industry: #{form[:industry]}" if form[:industry].present?
    lines << "Monthly volume: #{form[:volume]}" if form[:volume].present?
    lines << "Phone: #{form[:phone]}" if form[:phone].present?
    lines << '' << form[:message] if form[:message].present?
    (lines + extra_lines(form[:message])).join("\n")
  end

  # Site v3 extras. With JavaScript the site folds them into `message` itself; a plain (no-JS) POST sends them as
  # fields, so they are added here, each only when the message does not already carry that line.
  EXTRAS = { describe: 'In their words', business_type: 'Business type', channels: 'Channels',
             monthly: 'Monthly messages', pref_lang: 'Preferred language', time_window: 'Preferred time',
             result: 'Calculator result' }.freeze

  def extra_lines(message)
    EXTRAS.filter_map do |key, label|
      value = Array(params[key]).map { |v| v.to_s.strip }.compact_blank.join(', ').first(300)
      next if value.blank? || message.to_s.include?("#{label}:")

      "#{label}: #{value}"
    end
  end

  # Counts this request; true when its IP or the whole form is over the limit.
  def rate_limited?
    per_ip = over?("tolzar:site_contact:ip:#{request.remote_ip}", PER_IP_HOUR, 1.hour)
    per_day = over?("tolzar:site_contact:day:#{Time.current.utc.to_date}", GLOBAL_DAY, 1.day)
    per_ip || per_day
  end

  def over?(key, limit, window)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, window.to_i) if count == 1
    count > limit
  end

  def respond_ok
    return render(json: { ok: true }) if json_request?

    redirect = thanks_url
    redirect ? redirect_to(redirect, status: :see_other, allow_other_host: true) : render(plain: 'Thanks! We will reply by email.')
  end

  # The sending site's own thank-you page (the preview, tolzar.com or www), in the form's language.
  def thanks_url
    origin = page_origin
    return ENV.fetch('TOLZAR_CONTACT_REDIRECT', '').presence unless origin

    lang = params[:lang].to_s.strip.downcase
    lang.match?(/\A[a-z]{2}\z/) && lang != 'en' ? "#{origin}/#{lang}/thanks/" : "#{origin}/thanks/"
  end

  def page_origin
    [request.headers['Origin'], request.referer].each do |value|
      uri = URI.parse(value.to_s)
      next unless uri.is_a?(URI::HTTP) && uri.host.present?

      origin = uri.default_port == uri.port ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
      return origin if allowed_origins.include?(origin)
    rescue URI::InvalidURIError
      next
    end
    nil
  end

  def respond_error(status, error)
    json_request? ? render(json: { ok: false, error: error }, status: status) : render(plain: error.humanize, status: status)
  end

  def json_request?
    request.format.json? || request.content_mime_type&.json? || request.xhr?
  end

  def allowed_origins
    ENV.fetch('TOLZAR_CONTACT_ORIGINS', '').split(',').map(&:strip).compact_blank
  end

  def allowed_origin
    origin = request.headers['Origin'].to_s
    origin if origin.present? && allowed_origins.include?(origin)
  end

  def set_cors_headers
    return unless allowed_origin

    response.headers['Access-Control-Allow-Origin'] = allowed_origin
    response.headers['Vary'] = 'Origin'
    response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Max-Age'] = '600'
  end
end
