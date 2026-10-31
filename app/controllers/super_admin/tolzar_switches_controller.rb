# Tolzar Control Center: every TOLZAR_* switch of this app and of the brain, and the super admins' 2FA state
# (TOLZAR-APP-UI-REDESIGN-PLAN-2026-10-31.md phase 6, "Feature switches"). Read-only until after 12 Nov: switches are
# still set through Server ops' deploy path (env), never from the web. A value is shown only when it is plainly a
# switch (on/off, a number, an account list, a public URL); anything else reads "set" or "not set", never its value.
class SuperAdmin::TolzarSwitchesController < SuperAdmin::ApplicationController
  PLAIN = /\A(on|off|true|false|yes|no|enabled|disabled|[\d,\s]{1,200})\z/i
  PUBLIC_URL = %r{\Ahttps?://[a-z0-9.-]+(:\d+)?(/[\w./-]*)?\z}i
  HIDDEN_NAME = /(SECRET|PASSWORD|KEY|TOKEN|SALT|PRIVATE|CREDENTIAL|DSN)/

  def show
    @mfa = { requested: Tolzar::SuperAdminMfa.requested?, enforced: Tolzar::SuperAdminMfa.enforced?,
             missing: Tolzar::SuperAdminMfa.missing }
    @app_switches = ENV.keys.grep(/\ATOLZAR_/).sort.map { |name| { name: name, value: self.class.shown(name, ENV.fetch(name, nil)) } }
    @brain_switches = brain_switches
  end

  def self.shown(name, value)
    return 'not set' if value.blank?
    return 'set' if name.to_s.match?(HIDDEN_NAME)

    value = value.to_s.strip
    value.match?(PLAIN) || value.match?(PUBLIC_URL) ? value.first(200) : 'set'
  end

  private

  # The brain's own list (GET /switches): names with the same masking, applied again here.
  def brain_switches
    res = Tolzar::BrainClient.get('/switches')
    return unless res['status'] == 200

    Array(res['switches']).filter_map do |item|
      next unless item.is_a?(Hash) && item['name'].to_s.match?(/\A[A-Z][A-Z0-9_]{2,80}\z/)

      { name: item['name'], value: self.class.shown(item['name'], item['value']) }
    end
  rescue StandardError
    nil
  end
end
