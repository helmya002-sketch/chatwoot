# Tolzar shadow mirror: ensures the per-tenant Chatwoot destination exists —
# a mirror Account, a single API Inbox ("Respond.io Mirror"), and a generic
# mirror Agent for outgoing-message attribution. Everything is find_or_create
# (idempotent) and created DIRECTLY via ActiveRecord so NO invitation or
# confirmation email is ever sent.
#
# Safety: the inbox is a Channel::Api with no webhook_url (API channels do not
# deliver to customers), tagged additional_attributes[tolzar_mirror]=true so
# SendReplyJob hard-skips it, and the account never enables
# `email_continuity_on_api_channel`, so no email can reach a mirrored contact.
class Tolzar::Mirror::Bootstrap
  MIRROR_INBOX_NAME = 'Respond.io Mirror'.freeze
  AGENT_EMAIL_DOMAIN = 'tolzar.invalid'.freeze # RFC-2606 reserved, non-deliverable

  pattr_initialize [:tenant!]

  def account
    @account ||= begin
      acc = find_or_create_account
      link_observer(acc)
      acc
    end
  end

  def inbox
    @inbox ||= find_or_create_inbox
  end

  # The generic agent used to attribute outgoing/comment messages in the mirror.
  def agent
    @agent ||= find_or_create_agent('Respond.io', 'agent')
  end

  # Maps a specific respond.io user (e.g. an assignee) to a mirror agent.
  def agent_for(display_name, slug)
    find_or_create_agent(display_name, slug)
  end

  private

  def find_or_create_account
    acc_id = Tolzar::MirrorConfig.account_id(tenant)
    existing = acc_id && Account.find_by(id: acc_id)
    return existing if existing

    name = Tolzar::MirrorConfig.account_name(tenant) || "#{tenant} (mirror)"
    Account.find_or_create_by!(name: name)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    Account.find_by(name: name) || raise(e)
  end

  def find_or_create_inbox
    # The mirror tag lives on the API channel (inboxes have no additional_attributes).
    found = account.inboxes.find { |i| Tolzar::MirrorConfig.mirror_inbox?(i) }
    return ensure_inbox_config(found) if found

    tag = Tolzar::MirrorConfig::MIRROR_INBOX_TAG
    channel = Channel::Api.create!(
      account: account,
      webhook_url: nil, # no delivery target — API channels never reach a customer
      additional_attributes: { tag => true, 'source' => 'respond.io' }
    )
    account.inboxes.create!(
      name: MIRROR_INBOX_NAME,
      channel: channel,
      greeting_enabled: false,
      enable_email_collect: false,
      enable_auto_assignment: false,
      lock_to_single_conversation: true # one thread per contact, like respond.io
    )
  end

  # Self-heal an existing mirror inbox to the safe config (idempotent).
  def ensure_inbox_config(inbox)
    changes = {}
    changes[:lock_to_single_conversation] = true unless inbox.lock_to_single_conversation
    changes[:greeting_enabled] = false if inbox.greeting_enabled
    changes[:enable_email_collect] = false if inbox.enable_email_collect
    changes[:enable_auto_assignment] = false if inbox.enable_auto_assignment
    inbox.update!(changes) if changes.any?
    inbox
  end

  # Maps a respond.io display name to a Chatwoot agent user in this account.
  # slug keeps emails unique + stable; no real email is ever used.
  def find_or_create_agent(display_name, slug)
    email = "mirror-#{tenant}-#{slug}@#{AGENT_EMAIL_DOMAIN}".downcase
    user = find_or_create_user(email, display_name)
    link_user_to_account(user)
    user
  end

  def find_or_create_user(email, display_name)
    user = User.find_by(email: email)
    return user if user

    # Chatwoot requires a complex password (>=6, upper/lower/number/special).
    # This placeholder agent never logs in, so the value is irrelevant — it just
    # has to pass validation. "Mir9!" supplies all four classes.
    pw = "Mir9!#{SecureRandom.hex(20)}"
    user = User.new(name: display_name.presence || 'Agent', email: email,
                    password: pw, password_confirmation: pw)
    user.skip_confirmation!              # sets confirmed_at (account already confirmed)
    user.skip_confirmation_notification! # and never enqueue the confirmation email
    user.save!
    user
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    found = User.find_by(email: email)
    found || raise(e)
  end

  def link_user_to_account(user)
    AccountUser.find_or_create_by!(account_id: account.id, user_id: user.id) { |au| au.role = :agent }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # concurrent link (DB unique race, or the uniqueness VALIDATION firing first)
    # — the link already exists, nothing to do.
  end

  # Link the brain's read/write user (a Chatwoot user id in TOLZAR_MIRROR_OBSERVER_USER_ID)
  # to every mirror account as administrator, so the brain can read mirrored threads and
  # post its private "[Tolzar · would] …" eval notes on tenants beyond account 1. The brain
  # authenticates to Chatwoot with this user's token; a mirror account it is not a member of
  # returns 401. No-op when unset, when the user is missing, or when already linked.
  def link_observer(acc)
    uid = ENV['TOLZAR_MIRROR_OBSERVER_USER_ID'].to_i
    return if uid <= 0
    return unless User.exists?(id: uid)

    AccountUser.find_or_create_by!(account_id: acc.id, user_id: uid) { |au| au.role = :administrator }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # already linked (DB unique race, or the uniqueness validation firing first)
  end
end
