# Tolzar: two-factor sign-in for super admins (Control Center, TOLZAR-APP-UI-REDESIGN-PLAN-2026-10-31.md phase 6).
# TOLZAR_SUPERADMIN_2FA_REQUIRED (off by default) asks the /super_admin sign-in for the app's own one-time code (or a
# backup code) after the password. Lock-out guard (Oracle, 31 Oct): the switch takes effect only once EVERY super
# admin has 2FA set up in their profile; until then sign-in stays as it is and the Control Center lists who is missing.
module Tolzar::SuperAdminMfa
  module_function

  def requested?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('TOLZAR_SUPERADMIN_2FA_REQUIRED', '').presence) == true
  end

  def missing
    SuperAdmin.where(otp_required_for_login: [false, nil]).order(:email).pluck(:email)
  end

  def enforced?
    requested? && missing.empty?
  end

  # A 6-digit code is an authenticator code; anything else is tried as a backup code.
  def verify(user, code)
    code = code.to_s.strip
    return false if code.blank? || !user.otp_required_for_login?

    otp = code.match?(/\A\d{6}\z/)
    Mfa::AuthenticationService.new(user: user, otp_code: (code if otp), backup_code: (code unless otp)).authenticate
  end
end
