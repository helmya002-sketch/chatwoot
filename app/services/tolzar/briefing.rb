# Tolzar briefing bar (the full-width greeting line above the app): what needs this person now, from the
# conversations they may open (Conversations::PermissionFilterService: administrators all, agents their inboxes).
#   hot  open conversations whose contact's lead score (the brain's `tolzar_lead_score`) is >= HOT_SCORE; the top
#        LIMIT by score, and how many there are
# Read-only; nothing is estimated, so an empty list really means none.
class Tolzar::Briefing
  HOT_SCORE = 70 # the same rule as the inbox (tolzarAttention.js HOT_SCORE)
  LIMIT = 5
  RAW = "(contacts.custom_attributes->>'tolzar_lead_score')".freeze
  # A score that is not a plain number counts as none (CASE, so the cast never sees text).
  SCORE = "(CASE WHEN #{RAW} ~ '^[0-9]+([.][0-9]+)?$' THEN #{RAW}::numeric END)".freeze

  def initialize(account, user)
    @account = account
    @user = user
  end

  def report
    scope = hot_scope
    rows = scope.reorder(Arel.sql("#{SCORE} DESC, conversations.last_activity_at DESC")).limit(LIMIT)
                .pluck(:display_id, 'contacts.name', Arel.sql(SCORE), Arel.sql("contacts.custom_attributes->>'tolzar_lead_hint'"))
    { hot_count: scope.count,
      hot: rows.map { |id, name, score, hint| { id: id, name: name.to_s, score: score.to_f.round, hint: hint.to_s.first(140) } } }
  end

  private

  def hot_scope
    visible = Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
    visible.open.joins(:contact).where("#{SCORE} >= ?", HOT_SCORE)
  end
end
