# Tolzar booking-system connector (TOLZAR-BOOKING-DOCUMENTS-PLAN-2026-10-31.md §4): one external booking system per
# workspace (DWT Bookings is the first adapter). The token is encrypted at rest (Active Record encryption, as for
# channel credentials) and is never returned by the API.
class CreateTolzarBookingConnectors < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_booking_connectors do |t|
      t.bigint :account_id, null: false
      t.string :adapter, null: false
      t.string :base_url, null: false
      t.text :token
      t.datetime :last_test_at
      t.boolean :last_test_ok
      t.string :last_error
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :tolzar_booking_connectors, :account_id, unique: true
  end
end
