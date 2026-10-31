# Tolzar native bookings (TOLZAR-BOOKING-DOCUMENTS-PLAN-2026-10-31.md §5): multi-guest bookings with lines from the
# pack's line types, a payments RECORD (Tolzar never charges), statuses and history. The lines and payments use the
# booking documents' shapes (Tolzar::DocumentSpec), so a booking becomes a voucher or confirmation in one step.
class CreateTolzarBookings < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_bookings do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.bigint :conversation_id
      t.string :status, null: false, default: 'draft'
      t.string :currency, null: false, default: 'USD'
      t.date :starts_on
      t.date :ends_on
      t.bigint :total_cents, null: false, default: 0
      t.bigint :paid_cents, null: false, default: 0
      t.jsonb :data, null: false, default: {}
      t.jsonb :history, null: false, default: []
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :tolzar_bookings, [:account_id, :starts_on]
    add_index :tolzar_bookings, [:account_id, :status]
    add_index :tolzar_bookings, :contact_id
  end
end
