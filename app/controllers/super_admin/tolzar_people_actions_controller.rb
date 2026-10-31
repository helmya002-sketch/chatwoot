# Tolzar Control Center: sensitive actions on a person, each with a typed confirmation (their e-mail) and a reason,
# recorded in the audit log with that reason. Nothing here deletes a person or their data.
#   POST control_center/people/:id/reset_two_factor  turn two-factor sign-in off so they set it up again
#   POST control_center/people/:id/end_sessions      end every session and token (they sign in again)
#   POST control_center/people/:id/resend_invite     send the invitation / confirmation e-mail again
class SuperAdmin::TolzarPeopleActionsController < SuperAdmin::ApplicationController
  ACTIONS = %w[reset_two_factor end_sessions resend_invite].freeze

  skip_after_action :tolzar_audit
  before_action :set_user
  before_action :confirm!

  def reset_two_factor
    @user.mfa_service.disable_two_factor!
    done('reset_two_factor')
  end

  def end_sessions
    @user.update!(tokens: {})
    done('end_sessions')
  end

  def resend_invite
    @user.send_confirmation_instructions
    done('resend_invite')
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  # The person's e-mail typed exactly, and a reason of at least a few words.
  def confirm!
    return if params[:confirm].to_s.strip.casecmp?(@user.email.to_s) && params[:reason].to_s.strip.length >= 5

    redirect_to super_admin_tolzar_cc_people_path, alert: t('super_admin.control_center.people_confirm_needed')
  end

  def done(action)
    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: action, super_admin: current_super_admin,
                                    status: 302, record_id: @user.id, note: params[:reason])
    redirect_to super_admin_tolzar_cc_people_path, notice: t("super_admin.control_center.people_done.#{action}", email: @user.email)
  end
end
