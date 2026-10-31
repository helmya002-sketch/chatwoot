# Tolzar Control Center audit: every super-admin change (any non-GET request under /super_admin) and every
# super-admin sign-in attempt. It keeps who, what, when, the record and the NAMES of the fields sent; values are
# never stored, so a password, key or token typed into a form cannot land here.
class Tolzar::SuperAdminAudit < ApplicationRecord
  self.table_name = 'tolzar_super_admin_audits'

  SKIP_PARAMS = %w[controller action authenticity_token _method utf8 commit id format].freeze
  MAX_FIELDS = 50

  scope :recent, -> { order(created_at: :desc) }

  def self.record!(request:, controller:, action:, super_admin: nil, status: nil, email: nil, record_id: nil)
    create!(super_admin_id: super_admin&.id, email: (email || super_admin&.email).to_s.first(255).presence,
            controller: controller.to_s.first(120), action: action.to_s.first(60), http_method: request.request_method,
            path: request.path.to_s.first(500), record_id: record_id.to_s.first(64).presence,
            fields: field_names(request.request_parameters), status: status, ip: request.remote_ip, created_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[tolzar] super admin audit not written: #{e.class}")
    nil
  end

  # {"account" => {"name" => "x", "limits" => {"agents" => 1}}} -> ["account.limits.agents", "account.name"]
  def self.field_names(value, prefix = nil)
    names = case value
            when Hash, ActionController::Parameters
              value.to_h.flat_map do |key, inner|
                next [] if prefix.nil? && SKIP_PARAMS.include?(key.to_s)

                field_names(inner, [prefix, key.to_s.first(60)].compact.join('.'))
              end
            when Array then value.first(5).flat_map { |inner| field_names(inner, prefix) }
            else [prefix].compact
            end
    names.uniq.sort.first(MAX_FIELDS)
  end
end
