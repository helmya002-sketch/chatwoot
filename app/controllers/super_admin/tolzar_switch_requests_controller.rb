# Tolzar Control Center: asking for a switch change (Control Center plan: editing is owner-only, audited and only after
# 12 Nov; switches stay set through Server ops' deploy path, never written from the web). Before EDITING_FROM the form
# is shown disabled and this refuses; afterwards it records the request in the audit log (name, wanted value, reason)
# for Server ops to apply. No environment variable is ever written here.
class SuperAdmin::TolzarSwitchRequestsController < SuperAdmin::ApplicationController
  EDITING_FROM = Date.new(2026, 11, 12)
  NAME = /\ATOLZAR_[A-Z0-9_]{2,60}\z/
  VALUE = /\A[\w ,.:\/-]{0,200}\z/

  skip_after_action :tolzar_audit

  def self.open?(today = Date.current)
    today >= EDITING_FROM
  end

  def create
    return redirect_to(super_admin_tolzar_switches_path, alert: t('super_admin.tolzar_switches.request_closed')) unless self.class.open?

    name = params[:name].to_s.strip
    value = params[:value].to_s.strip
    reason = params[:reason].to_s.strip
    unless name.match?(NAME) && value.match?(VALUE) && !name.match?(SuperAdmin::TolzarSwitchesController::HIDDEN_NAME) && reason.length >= 5
      return redirect_to(super_admin_tolzar_switches_path, alert: t('super_admin.tolzar_switches.request_invalid'))
    end

    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: 'switch_change_request',
                                    super_admin: current_super_admin, status: 302, record_id: name, note: "#{name}=#{value} · #{reason}")
    redirect_to super_admin_tolzar_switches_path, notice: t('super_admin.tolzar_switches.request_saved', name: name)
  end
end
