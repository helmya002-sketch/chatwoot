# Tolzar B2 (first-paying-customer blocker, Oracle 30 Oct; switch TOLZAR_AUTO_PROVISION, default off): every new
# workspace gets its AI without anyone wiring it by hand.
# - Every new inbox (not a respond.io mirror inbox, not one that already has a bot) is attached to Tolzar's
#   system brain bot (TOLZAR_BRAIN_BOT_ID: an AgentBot with no account, i.e. a system bot whose secret no
#   workspace admin can see).
# - Deliveries to the brain are signed with the workspace's own derived key,
#   HKDF-SHA256(BRAIN_WEBHOOK_SECRET, info "tolzar-hook-v1:<account>") (the same key as the mirror's
#   BrainNotifyJob), which the brain already verifies for any account. So TOLZAR_AGENT_BOT_ACCOUNTS stops being a
#   manual list, and one workspace's key cannot sign for another.
# The brain starts every unknown workspace on its generic default in SHADOW (drafts as private notes); going
# live stays the Owner's per-inbox gate, unchanged.
module Tolzar::BrainProvisioning
  module_function

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('TOLZAR_AUTO_PROVISION', false))
  end

  def bot
    id = ENV.fetch('TOLZAR_BRAIN_BOT_ID', '').to_i
    id.positive? ? AgentBot.find_by(id: id, account_id: nil) : nil
  end

  # Attaches the system brain bot to a new inbox. Returns the AgentBotInbox, or nil when nothing was attached.
  def attach(inbox)
    return unless enabled?
    return if Tolzar::MirrorConfig.mirror_inbox?(inbox) || AgentBotInbox.exists?(inbox_id: inbox.id)

    brain_bot = bot
    unless brain_bot
      Rails.logger.error("[Tolzar] auto-provision: TOLZAR_BRAIN_BOT_ID is not a system bot; inbox #{inbox.id} has no AI")
      return
    end
    AgentBotInbox.create!(inbox: inbox, agent_bot: brain_bot, status: :active)
  end

  # True for a delivery that goes to the brain (its host is the brain's).
  def brain_url?(url)
    host = URI.parse(url.to_s).host
    host.present? && host == Tolzar::BrainClient.brain_host
  rescue URI::InvalidURIError
    false
  end

  # The workspace's own signing key (raw 32 bytes), or nil without BRAIN_WEBHOOK_SECRET or an account.
  def signing_key(account_id)
    master = ENV.fetch('BRAIN_WEBHOOK_SECRET', '').to_s
    return if master.empty? || account_id.to_i <= 0

    Tolzar::Mirror::BrainNotifyJob.derive_hook_key(master, account_id)
  end

  # Deliveries to the brain are signed per workspace while the switch is on (the listener then sends no secret).
  def sign_per_workspace?(url)
    enabled? && brain_url?(url)
  end
end
