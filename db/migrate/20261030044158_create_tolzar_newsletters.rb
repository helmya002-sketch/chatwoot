# Tolzar: the self-hosted newsletter to the app's own users (owner decision 30 Oct 2026: users only, our own
# sender on our server and domain, no third-party newsletter service). Three tables of our own, so the users
# table is untouched:
#   tolzar_newsletters            one issue: subject, Markdown body, language filter, status and counters
#   tolzar_newsletter_deliveries  one row per issue and user (unique): the send queue, idempotent
#   tolzar_newsletter_recipients  one row per user who opted out, bounced or was suppressed by hand
class CreateTolzarNewsletters < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_newsletters do |t|
      t.string :subject, null: false
      t.text :body_markdown, null: false
      t.string :locale                       # nil = every user; else only users whose language is this one
      t.string :status, null: false, default: 'draft' # draft -> sending -> sent
      t.bigint :created_by_id                # the super admin who wrote it
      t.integer :recipients_count, null: false, default: 0
      t.datetime :sending_started_at
      t.datetime :sent_at
      t.timestamps
    end
    add_index :tolzar_newsletters, :status

    create_table :tolzar_newsletter_deliveries do |t|
      t.bigint :newsletter_id, null: false
      t.bigint :user_id, null: false
      t.string :email, null: false           # the address it went to (a user may change theirs later)
      t.string :status, null: false, default: 'queued' # queued -> sending -> sent | failed | skipped | bounced
      t.string :message_id                   # our Message-ID header, matched by the Postal webhook
      t.string :error
      t.datetime :sent_at
      t.timestamps
    end
    add_index :tolzar_newsletter_deliveries, [:newsletter_id, :user_id], unique: true, name: 'idx_tz_nl_deliveries_newsletter_user'
    add_index :tolzar_newsletter_deliveries, [:newsletter_id, :status]
    add_index :tolzar_newsletter_deliveries, :message_id, unique: true, where: 'message_id IS NOT NULL'
    add_index :tolzar_newsletter_deliveries, :sent_at

    create_table :tolzar_newsletter_recipients do |t|
      t.bigint :user_id, null: false
      t.datetime :opted_out_at               # the user's own choice (one-click unsubscribe); only the user undoes it
      t.datetime :suppressed_at              # hard bounce, repeated soft bounces, a complaint, or a super admin
      t.string :suppression_reason
      t.jsonb :soft_bounces, null: false, default: [] # ISO times of soft bounces, the last 30 days kept
      t.timestamps
    end
    add_index :tolzar_newsletter_recipients, :user_id, unique: true
  end
end
