# Tolzar hardening (Oracle, item J): one env list of the hostnames this app serves, used for the Rails Host
# allow-list (config/environments/production.rb) and ActionCable's request origins (config/initializers/cors.rb).
#   TOLZAR_ALLOWED_HOSTS="chat.xplorer-redsea.com,app.tolzar.com,localhost,<internal docker names>"
# Empty (the default): no allow-list and any cable origin, as upstream.
module TolzarAllowedHosts
  module_function

  def hosts
    ENV.fetch('TOLZAR_ALLOWED_HOSTS', '').split(',').map { |h| h.strip.downcase }.reject(&:empty?)
  end

  def enabled?
    hosts.any?
  end

  # A websocket from a browser carries an Origin; it must be one of our hosts. No Origin at all (native apps,
  # server-side clients) is let through: a browser always sends one, so it cannot be used for cross-site abuse.
  def cable_origin_allowed?(origin)
    return true if origin.nil? || origin.to_s.strip.empty?

    host = URI.parse(origin.to_s).host.to_s.downcase
    hosts.include?(host)
  rescue URI::InvalidURIError
    false
  end
end
