# Tolzar follow-up reminders (round 4, E4): "remind me in 1 / 2 / 3 days if the customer doesn't answer", one per
# person per conversation. set_at is when it was set (a customer message after it cancels the reminder).
class CreateTolzarFollowUpReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_follow_up_reminders do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_id, null: false
      t.datetime :due_at, null: false
      t.datetime :set_at, null: false
      t.timestamps
    end
    add_index :tolzar_follow_up_reminders, [:conversation_id, :user_id], unique: true
    add_index :tolzar_follow_up_reminders, [:account_id, :due_at]
    add_index :tolzar_follow_up_reminders, [:user_id, :due_at]
  end
end
