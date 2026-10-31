# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    unless valid_credentials?
      audit_sign_in('sign_in_failed')
      return redirect_to(super_admin_session_path, flash: { error: @error_message })
    end

    sign_in(:super_admin, @super_admin)
    audit_sign_in('sign_in')
    flash.discard
    redirect_to super_admin_root_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  # Tolzar::SuperAdminAudit: the e-mail tried and the outcome; never the password or the code.
  def audit_sign_in(action)
    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: action,
                                    super_admin: (@super_admin if action == 'sign_in'),
                                    email: params.dig(:super_admin, :email).to_s.downcase)
  end

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])
    # Tolzar::SuperAdminMfa: the one-time code, only once every super admin has 2FA (off by default).
    raise StandardError, 'Invalid one-time code' if Tolzar::SuperAdminMfa.enforced? &&
                                                    !Tolzar::SuperAdminMfa.verify(@super_admin, params[:super_admin][:otp_code])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = 'Invalid credentials. Please try again.'
    false
  end
end
