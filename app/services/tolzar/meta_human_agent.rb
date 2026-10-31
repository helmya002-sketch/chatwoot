# Tolzar: Meta's HUMAN_AGENT message tag for Messenger and Instagram (owner-approved, round 4, c77), for the workspaces
# in TOLZAR_META_HUMAN_AGENT. Meta's standard window is 24 hours after the customer's last message; with the tag, a
# PERSON may reply up to 7 days after it (the app needs Meta's "Human Agent" permission, granted in its own App Review).
#   - a person's reply between 24 hours and 7 days goes out with messaging_type MESSAGE_TAG, tag HUMAN_AGENT, and
#     the message records that it did (content_attributes tolzar_human_agent_tag), for the audit
#   - the AI and bots never use it: an agent bot, the brain's own user (TOLZAR_BRAIN_USER_IDS, the user the brain
#     falls back to) and any message marked tolzar_ai are not a person. Fail closed: with no brain user listed,
#     nothing is tagged at all
#   - after 7 days nobody can reply (the composer says why); WhatsApp is unchanged (24 hours, then templates)
# Not active until Meta grants Human Agent and the owner says go (the switch is empty by default).
module Tolzar::MetaHumanAgent
  STANDARD = 24.hours
  HUMAN_AGENT = 7.days
  CHANNELS = %w[Channel::FacebookPage Channel::Instagram].freeze

  module_function

  def ids(name)
    ENV.fetch(name, '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def on?(account_id)
    ids('TOLZAR_META_HUMAN_AGENT').include?(account_id.to_i) && ids('TOLZAR_BRAIN_USER_IDS').any?
  end

  def person?(message)
    message.sender.is_a?(User) && !ids('TOLZAR_BRAIN_USER_IDS').include?(message.sender_id) &&
      !ActiveModel::Type::Boolean.new.cast((message.content_attributes || {})['tolzar_ai'])
  end

  # The tag goes on a person's public reply sent after the 24-hour window and inside the 7-day one.
  def tag?(message)
    return false unless on?(message.account_id) && person?(message) && !message.private?

    last = last_incoming_at(message.conversation)
    last.present? && last < STANDARD.ago && last > HUMAN_AGENT.ago
  end

  def record!(message)
    message.update_columns(content_attributes: (message.content_attributes || {}).merge('tolzar_human_agent_tag' => true))
    Rails.logger.info("[Tolzar] HUMAN_AGENT tag on message #{message.id} (account #{message.account_id}, user #{message.sender_id})")
  end

  # How long a person may still reply, for the composer: standard (inside 24 hours), human_agent (24 hours to 7 days,
  # switch on), closed, or nil for channels without such a window.
  def window(conversation, now = Time.current)
    return nil unless CHANNELS.include?(conversation.inbox&.channel_type)

    last = last_incoming_at(conversation)
    return { kind: 'closed', ends_at: nil } if last.nil?
    return { kind: 'standard', ends_at: last + STANDARD } if now < last + STANDARD
    return { kind: 'human_agent', ends_at: last + HUMAN_AGENT } if on?(conversation.account_id) && now < last + HUMAN_AGENT

    { kind: 'closed', ends_at: nil }
  end

  def last_incoming_at(conversation)
    conversation&.messages&.where(account_id: conversation.account_id)&.incoming&.maximum(:created_at)
  end
end
