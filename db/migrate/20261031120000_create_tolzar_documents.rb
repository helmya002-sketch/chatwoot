# Tolzar booking documents (TOLZAR-BOOKING-DOCUMENTS-PLAN-2026-10-31.md §1): vouchers, quotes, booking
# confirmations and payment summaries. A document is a draft until issued; issuing gives it a gapless number per
# workspace, type and year (tolzar_document_counters, row-locked). A voided document keeps its number.
class CreateTolzarDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_documents do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id
      t.bigint :contact_id
      t.string :doc_type, null: false
      t.string :status, null: false, default: 'draft'
      t.string :number
      t.integer :year
      t.integer :seq
      t.string :currency, null: false, default: 'USD'
      t.bigint :total_cents, null: false, default: 0
      t.bigint :paid_cents, null: false, default: 0
      t.string :language, null: false, default: 'en'
      t.jsonb :spec, null: false, default: {}
      t.jsonb :history, null: false, default: []
      t.integer :version, null: false, default: 1
      t.bigint :created_by_id
      t.datetime :issued_at
      t.bigint :issued_by_id
      t.datetime :voided_at
      t.string :void_reason
      t.timestamps
    end
    add_index :tolzar_documents, [:account_id, :number], unique: true
    add_index :tolzar_documents, [:account_id, :created_at]
    add_index :tolzar_documents, :conversation_id
    add_index :tolzar_documents, :contact_id

    create_table :tolzar_document_counters do |t|
      t.bigint :account_id, null: false
      t.string :doc_type, null: false
      t.integer :year, null: false
      t.integer :last_seq, null: false, default: 0
      t.timestamps
    end
    add_index :tolzar_document_counters, [:account_id, :doc_type, :year], unique: true, name: 'index_tolzar_document_counters_unique'
  end
end
