# Tolzar Control Center: the reason a super admin typed for a sensitive action (reset 2FA, sign out everywhere,
# pause / resume a workspace). Free text the super admin wrote; never a secret.
class AddNoteToTolzarSuperAdminAudits < ActiveRecord::Migration[7.1]
  def change
    add_column :tolzar_super_admin_audits, :note, :string, limit: 300
  end
end
