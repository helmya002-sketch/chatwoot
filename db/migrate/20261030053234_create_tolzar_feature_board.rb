# Tolzar: the public feature-request board, roadmap and changelog inside the app (owner-approved community plan,
# 30 Oct 2026). Reading is public; posting, voting and commenting need a Tolzar login with a workspace.
#   tolzar_ideas                 one idea (#id): status, tag, language, author, moderation state, merged duplicate
#   tolzar_idea_votes            one vote per idea and user (unique); shipped_notified_at = the ship email went out
#   tolzar_idea_comments         replies; staff explanations are pinned; a first post is held for review
#   tolzar_idea_status_changes   the dated status history, each change with its explanation
#   tolzar_changelog_entries     published release notes; an idea points at the entry that shipped it
# No foreign keys (fork convention); the models carry the associations.
class CreateTolzarFeatureBoard < ActiveRecord::Migration[7.1]
  def change
    create_table :tolzar_ideas do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :status, null: false, default: 'under_review'
      t.string :tag
      t.string :locale, null: false                    # the language the idea is written in
      t.bigint :user_id                                # the author
      t.bigint :account_id                             # the author's workspace when posting
      t.integer :votes_count, null: false, default: 0
      t.bigint :merged_into_id                         # set when merged into another idea as a duplicate
      t.bigint :changelog_entry_id                     # the changelog entry that shipped it
      t.boolean :held, null: false, default: false     # an account's first post, waiting for a moderator
      t.boolean :hidden, null: false, default: false   # hidden by a moderator
      t.integer :reports_count, null: false, default: 0
      t.jsonb :reporter_ids, null: false, default: []  # one report per user
      t.timestamps
    end
    add_index :tolzar_ideas, [:status, :votes_count]
    add_index :tolzar_ideas, :user_id
    add_index :tolzar_ideas, :merged_into_id
    add_index :tolzar_ideas, :changelog_entry_id

    create_table :tolzar_idea_votes do |t|
      t.bigint :idea_id, null: false
      t.bigint :user_id, null: false
      t.datetime :shipped_notified_at
      t.timestamps
    end
    add_index :tolzar_idea_votes, [:idea_id, :user_id], unique: true
    add_index :tolzar_idea_votes, :user_id
    add_index :tolzar_idea_votes, :created_at

    create_table :tolzar_idea_comments do |t|
      t.bigint :idea_id, null: false
      t.bigint :user_id
      t.text :body, null: false
      t.boolean :staff, null: false, default: false
      t.boolean :pinned, null: false, default: false
      t.boolean :held, null: false, default: false
      t.boolean :hidden, null: false, default: false
      t.integer :reports_count, null: false, default: 0
      t.jsonb :reporter_ids, null: false, default: []
      t.timestamps
    end
    add_index :tolzar_idea_comments, [:idea_id, :created_at]
    add_index :tolzar_idea_comments, :user_id

    create_table :tolzar_idea_status_changes do |t|
      t.bigint :idea_id, null: false
      t.string :from_status
      t.string :to_status, null: false
      t.text :explanation, null: false
      t.bigint :changed_by_id                          # the super admin
      t.datetime :created_at, null: false
    end
    add_index :tolzar_idea_status_changes, [:idea_id, :created_at]

    create_table :tolzar_changelog_entries do |t|
      t.string :title, null: false
      t.text :body_markdown, null: false
      t.datetime :published_at                         # nil = draft
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :tolzar_changelog_entries, :published_at
  end
end
