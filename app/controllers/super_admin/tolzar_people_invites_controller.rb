# Tolzar Control Center (round 4, c86): invite a person to a workspace from the console. The workspace's name typed
# exactly and a reason; the role is agent or administrator (never more); a new person gets Chatwoot's own
# confirmation e-mail. No inviter is recorded (it was the console, not a member). Audited with the reason. Nothing
# else about the workspace changes; an existing member is left as they are.
#   POST control_center/people/invite  {account_id, email, name, role, confirm, reason}
class SuperAdmin::TolzarPeopleInvitesController < SuperAdmin::ApplicationController
  ROLES = %w[agent administrator].freeze
  EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  skip_after_action :tolzar_audit

  def create
    account = Account.find_by(id: params[:account_id])
    email = params[:email].to_s.strip.downcase
    return refuse('people_invite_invalid') unless account && email.match?(EMAIL) && ROLES.include?(params[:role].to_s)
    return refuse('people_invite_confirm_needed') unless params[:confirm].to_s.strip == account.name && params[:reason].to_s.strip.length >= 5

    user = invite(account, email, params[:name].to_s.strip.first(100).presence || email.split('@').first, params[:role].to_s)
    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: 'invite', super_admin: current_super_admin,
                                    status: 302, record_id: user.id, note: "#{account.id} #{params[:role]} · #{params[:reason]}")
    redirect_to super_admin_tolzar_cc_people_path, notice: t('super_admin.control_center.people_done.invite', email: email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to super_admin_tolzar_cc_people_path, alert: e.record.errors.full_messages.first
  end

  private

  def invite(account, email, name, role)
    ActiveRecord::Base.transaction do
      user = User.find_by(email: email) || create_user(email, name)
      AccountUser.find_or_create_by!(account: account, user: user) { |au| au.role = role }
      user.send_confirmation_instructions unless user.confirmed?
      user
    end
  end

  def create_user(email, name)
    password = "#{SecureRandom.alphanumeric(24)}aA1!"
    User.new(email: email, name: name, password: password, password_confirmation: password).tap do |user|
      user.skip_confirmation_notification!
      user.save!
    end
  end

  def refuse(key)
    redirect_to super_admin_tolzar_cc_people_path, alert: t("super_admin.control_center.#{key}")
  end
end
