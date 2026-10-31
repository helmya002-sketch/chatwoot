# Tolzar Control Center: a super admin's manual hold on a workspace (pause / resume), separate from billing lapses so
# it can never schedule a purge: a held workspace is "paused" (read-only, AI off when billing is enforced) until it is
# resumed, with no purge date.
class AddHoldToTolzarSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_column :tolzar_subscriptions, :held_at, :datetime
    add_column :tolzar_subscriptions, :held_reason, :string, limit: 300
  end
end
