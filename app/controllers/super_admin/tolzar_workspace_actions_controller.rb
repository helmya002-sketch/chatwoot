# Tolzar Control Center: hold (pause) or release (resume) a workspace, with the workspace's name typed and a reason,
# audited with that reason (Tolzar::Subscription#hold! / #release!). A hold never schedules a purge; deleting or
# purging a workspace is not available here (the owner's own action elsewhere).
#   POST control_center/workspaces/:id/hold
#   POST control_center/workspaces/:id/release
class SuperAdmin::TolzarWorkspaceActionsController < SuperAdmin::ApplicationController
  skip_after_action :tolzar_audit
  before_action :set_account
  before_action :confirm!

  def hold
    Tolzar::Subscription.for(@account).hold!(reason: params[:reason])
    done('hold')
  end

  def release
    Tolzar::Subscription.for(@account).release!
    done('release')
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def confirm!
    return if params[:confirm].to_s.strip == @account.name.to_s.strip && params[:reason].to_s.strip.length >= 5

    redirect_to super_admin_tolzar_cc_workspace_path(@account), alert: t('super_admin.control_center.workspace_confirm_needed')
  end

  def done(action)
    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: action, super_admin: current_super_admin,
                                    status: 302, record_id: @account.id, note: params[:reason])
    redirect_to super_admin_tolzar_cc_workspace_path(@account), notice: t("super_admin.control_center.workspace_done.#{action}")
  end
end
