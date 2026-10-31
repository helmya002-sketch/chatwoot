# Tolzar Control Center (round 4, c86): a deactivated person cannot sign in (web or API) until reactivated. Nothing of
# theirs is deleted; the timestamp is the whole state.
class AddTolzarDeactivatedAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :tolzar_deactivated_at, :datetime
  end
end
