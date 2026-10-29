# This class creates both outgoing messages from chatwoot and echo outgoing messages based on the flag `outgoing_echo`
# Assumptions
# 1. Incase of an outgoing message which is echo, source_id will NOT be nil,
#    based on this we are showing "not sent from chatwoot" message in frontend
#    Hence there is no need to set user_id in message for outgoing echo messages.

class Messages::Facebook::MessageBuilder < Messages::Messenger::MessageBuilder
  attr_reader :response

  # Tolzar: a standalone referral that found no conversation waits here for the contact's next message.
  PENDING_REFERRAL_KEY = 'TOLZAR_FB_PENDING_REFERRAL::%<inbox_id>s::%<sender_id>s'.freeze
  PENDING_REFERRAL_TTL = 1.day

  def initialize(response, inbox, outgoing_echo: false)
    super()
    @response = response
    @inbox = inbox
    @outgoing_echo = outgoing_echo
    @sender_id = (@outgoing_echo ? @response.recipient_id : @response.sender_id)
    @message_type = (@outgoing_echo ? :outgoing : :incoming)
    @attachments = (@response.attachments || [])
  end

  def perform
    # This channel might require reauthorization, may be owner might have changed the fb password
    return if @inbox.channel.reauthorization_required?

    ActiveRecord::Base.transaction do
      build_contact_inbox
      response.standalone_referral? ? store_standalone_referral : build_message
    end
  rescue Koala::Facebook::AuthenticationError => e
    Rails.logger.warn("Facebook authentication error for inbox: #{@inbox.id} with error: #{e.message}")
    Rails.logger.error e
    @inbox.channel.authorization_error!
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    true
  end

  private

  def build_contact_inbox
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: @sender_id,
      inbox: @inbox,
      contact_attributes: contact_params
    ).perform
  end

  def build_message
    @message = conversation.messages.create!(message_params)
    store_conversation_referral(conversation, @referral) if @referral.present?

    @attachments.each do |attachment|
      process_attachment(attachment)
    end
  end

  # Tolzar (Messenger attribution): an incoming message carries the referral it came with (inside a
  # postback / message), else one a standalone referral event left for this contact.
  def incoming_referral
    return if @outgoing_echo

    response.referral_attributes || pop_pending_referral
  end

  # A standalone referral event creates no message: it goes on the contact's open conversation
  # (additional_attributes.referral / referral_ref), or waits for the contact's next message.
  def store_standalone_referral
    referral = response.referral_attributes
    return if referral.blank?

    existing = existing_conversation
    if existing
      store_conversation_referral(existing, referral, overwrite: true)
    else
      Redis::Alfred.setex(pending_referral_key, referral.to_json, PENDING_REFERRAL_TTL)
    end
  end

  # First touch wins on a conversation unless a standalone referral event says otherwise.
  def store_conversation_referral(target, referral, overwrite: false)
    attrs = (target.additional_attributes || {}).dup
    return if attrs['referral'].present? && !overwrite

    target.update!(additional_attributes: attrs.merge('referral' => referral, 'referral_ref' => referral['ref']))
  end

  def existing_conversation
    scope = Conversation.where(conversation_params)
    scope = scope.where.not(status: :resolved) unless @inbox.lock_to_single_conversation
    scope.order(created_at: :desc).first
  end

  def pending_referral_key
    format(PENDING_REFERRAL_KEY, inbox_id: @inbox.id, sender_id: @sender_id)
  end

  def pop_pending_referral
    raw = Redis::Alfred.get(pending_referral_key)
    return if raw.blank?

    Redis::Alfred.delete(pending_referral_key)
    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) && parsed['ref'].present? ? parsed.slice(*Integrations::Facebook::MessageParser::REFERRAL_KEYS) : nil
  rescue JSON::ParserError
    nil
  end

  def conversation
    @conversation ||= set_conversation_based_on_inbox_config
  end

  def set_conversation_based_on_inbox_config
    if @inbox.lock_to_single_conversation
      Conversation.where(conversation_params).order(created_at: :desc).first || build_conversation
    else
      find_or_build_for_multiple_conversations
    end
  end

  def find_or_build_for_multiple_conversations
    # If lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    last_conversation = Conversation.where(conversation_params).where.not(status: :resolved).order(created_at: :desc).first
    return build_conversation if last_conversation.nil?

    last_conversation
  end

  def build_conversation
    Conversation.create!(conversation_params.merge(
                           contact_inbox_id: @contact_inbox.id
                         ))
  end

  def location_params(attachment)
    lat = attachment['payload']['coordinates']['lat']
    long = attachment['payload']['coordinates']['long']
    {
      external_url: attachment['url'],
      coordinates_lat: lat,
      coordinates_long: long,
      fallback_title: attachment['title']
    }
  end

  def fallback_params(attachment)
    {
      fallback_title: attachment['title'] || attachment.dig('payload', 'title'),
      external_url: attachment['url'] || attachment.dig('payload', 'url')
    }
  end

  # Facebook shared posts point to page URLs, not downloadable media URLs.
  # Both `share` and `post` attachment types carry a page URL rather than a media file,
  # so map them to `fallback` (which keeps the title/link without attempting a download).
  # Keep this Facebook-only so Messenger/Instagram share attachments still use the parent media handling.
  def normalize_file_type(type)
    return :fallback if [:share, :post].include?(type.to_sym)

    super
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact_inbox.contact_id
    }
  end

  def message_params
    content_attributes = {
      in_reply_to_external_id: response.in_reply_to_external_id
    }
    content_attributes[:external_echo] = true if @outgoing_echo
    @referral = incoming_referral
    content_attributes[:referral] = @referral if @referral.present?

    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: @message_type,
      status: @outgoing_echo ? :delivered : :sent,
      content: response.content,
      source_id: response.identifier,
      content_attributes: content_attributes,
      sender: @outgoing_echo ? nil : @contact_inbox.contact
    }
  end

  # Tolzar: a sender whose profile Meta does not share (no app role, or no profile access) is a
  # neutral "Messenger user", not an invented person's name.
  def process_contact_params_result(result)
    name = result['name'].presence || [result['first_name'], result['last_name']].compact_blank.join(' ').presence || 'Messenger user'

    {
      name: name,
      account_id: @inbox.account_id,
      avatar_url: result['profile_pic']
    }
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/MethodLength
  def contact_params
    begin
      k = Koala::Facebook::API.new(@inbox.channel.page_access_token) if @inbox.facebook?
      result = k.get_object(@sender_id) || {}
    rescue Koala::Facebook::AuthenticationError => e
      Rails.logger.warn("Facebook authentication error for inbox: #{@inbox.id} with error: #{e.message}")
      Rails.logger.error e
      @inbox.channel.authorization_error!
      raise
    rescue Koala::Facebook::ClientError => e
      result = {}
      # OAuthException, code: 100, error_subcode: 2018218, message: (#100) No profile available for this user
      # We don't need to capture this error as we don't care about contact params in case of echo messages
      if e.message.include?('2018218')
        Rails.logger.warn e
      else
        ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception unless @outgoing_echo
      end
    rescue StandardError => e
      result = {}
      ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    end
    process_contact_params_result(result)
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength
end
