# TODO: lets use HTTParty instead of RestClient
class ChatwootHub
  DEFAULT_BASE_URL = ''.freeze   # Tolzar: no Chatwoot hub (never called; see sync_with_hub)

  def self.base_url
    DEFAULT_BASE_URL
  end

  def self.ping_url
    "#{base_url}/ping"
  end

  def self.registration_url
    "#{base_url}/instances"
  end

  def self.push_notification_url
    "#{base_url}/send_push"
  end

  def self.events_url
    "#{base_url}/events"
  end

  def self.billing_base_url
    "#{base_url}/billing"
  end

  def self.installation_identifier
    identifier = InstallationConfig.find_by(name: 'INSTALLATION_IDENTIFIER')&.value
    identifier ||= InstallationConfig.create!(name: 'INSTALLATION_IDENTIFIER', value: SecureRandom.uuid).value
    identifier
  end

  def self.billing_url
    "#{billing_base_url}?installation_identifier=#{installation_identifier}"
  end

  def self.pricing_plan
    return 'community' unless ChatwootApp.enterprise?

    InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value || 'community'
  end

  def self.pricing_plan_quantity
    return 0 unless ChatwootApp.enterprise?

    InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')&.value || 0
  end

  def self.support_config
    {
      support_website_token: InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_WEBSITE_TOKEN')&.value,
      support_script_url: InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_SCRIPT_URL')&.value,
      support_identifier_hash: InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_IDENTIFIER_HASH')&.value
    }
  end

  def self.instance_config
    {
      installation_identifier: installation_identifier,
      installation_version: Chatwoot.config[:version],
      installation_host: URI.parse(ENV.fetch('FRONTEND_URL', '')).host,
      installation_env: ENV.fetch('INSTALLATION_ENV', ''),
      edition: ENV.fetch('CW_EDITION', '')
    }
  end

  def self.instance_metrics
    {
      accounts_count: fetch_count(Account),
      users_count: fetch_count(User),
      inboxes_count: fetch_count(Inbox),
      conversations_count: fetch_count(Conversation),
      incoming_messages_count: fetch_count(Message.incoming),
      outgoing_messages_count: fetch_count(Message.outgoing),
      additional_information: {}
    }
  end

  def self.fetch_count(model)
    model.last&.id || 0
  end

  # Kept for callers that still ask; Tolzar never calls the hub whatever it says (see below).
  def self.telemetry_disabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('DISABLE_TELEMETRY', false))
  end

  # Tolzar: no network call to Chatwoot's hub, ever (owner rule, 29 Oct 2026: never depend on
  # Chatwoot). No version ping, no instance registration, no events, no push relay: mobile push goes
  # through the install's own Firebase project (FIREBASE_PROJECT_ID + FIREBASE_CREDENTIALS), web push
  # through its own VAPID keys. The URL helpers stay only so old call sites keep compiling.
  def self.sync_with_hub
    nil
  end

  def self.register_instance(_company_name, _owner_name, _owner_email)
    nil
  end

  def self.send_push(_fcm_options)
    Rails.logger.warn('[Tolzar] mobile push needs FIREBASE_PROJECT_ID + FIREBASE_CREDENTIALS (no Chatwoot relay)')
    nil
  end

  def self.send_push_with_response(_fcm_options)
    raise 'Tolzar has no push relay: set FIREBASE_PROJECT_ID and FIREBASE_CREDENTIALS for mobile push'
  end

  def self.emit_event(_event_name, _event_data)
    nil
  end
end

ChatwootHub.singleton_class.prepend_mod_with('ChatwootHub')
