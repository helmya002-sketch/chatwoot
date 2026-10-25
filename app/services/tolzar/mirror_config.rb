# Tolzar shadow mirror: tenant registry + respond.io webhook signature check.
#
# Signing keys are per webhook (respond.io generates one per event), supplied as a
# comma-separated list per tenant via env (never in the repo):
#   TOLZAR_MIRROR_KEYS_AQUARIUS="key1,key2,..."
#   TOLZAR_MIRROR_KEYS_XPLORER="key1,key2,..."
# A request is accepted if its X-Webhook-Signature matches ANY of that tenant's keys
# (base64(HMAC-SHA256(key, raw_body)), per respond.io's docs).
require 'openssl'
require 'base64'

module Tolzar
  module MirrorConfig
    CONFIG_PATH = Rails.root.join('config', 'tolzar_mirror.yml')

    module_function

    def config
      @config ||= (YAML.safe_load(File.read(CONFIG_PATH)) || {}).freeze
    end

    def tenants
      config['tenants'] || {}
    end

    def tenant?(name)
      tenants.key?(name.to_s)
    end

    def account_id(name)
      tenants.dig(name.to_s, 'account_id')
    end

    def signing_keys(tenant)
      ENV.fetch("TOLZAR_MIRROR_KEYS_#{tenant.to_s.upcase}", '')
         .split(',').map(&:strip).reject(&:empty?)
    end

    def valid_signature?(tenant, raw_body, signature)
      return false if signature.to_s.empty?

      signing_keys(tenant).any? do |key|
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', key, raw_body))
        ActiveSupport::SecurityUtils.secure_compare(signature, expected)
      end
    end
  end
end
