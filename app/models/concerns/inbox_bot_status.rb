module InboxBotStatus
  extend ActiveSupport::Concern

  def active_bot?
    external_bot_active?
  end

  def external_bot_active?
    agent_bot_inbox&.active? || dialogflow_active?
  end

  # Tolzar: the active agent bot is the Tolzar brain in shadow (AgentBot#tolzar_shadow?). Its conversations
  # start (and reopen) as open, visible to the team, instead of pending for a bot that never hands off.
  def tolzar_shadow_bot?
    return false unless agent_bot_inbox&.active?

    agent_bot&.tolzar_shadow? || false
  end

  private

  def dialogflow_active?
    hooks.exists?(app_id: %w[dialogflow], status: 'enabled')
  end
end
