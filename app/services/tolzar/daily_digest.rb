# Tolzar owner's daily digest (round 4, c89), for the workspaces in TOLZAR_DIGEST_ACCOUNTS: one internal e-mail a day to
# the workspace owner (Tolzar::AccountOwner), never to a customer. Yesterday (UTC) and right now, from the
# workspace's own records; nothing is estimated.
#   yesterday  new conversations, customer messages, replies sent by the team, conversations resolved
#   now        open, waiting for a reply (Chatwoot's Unattended rule), hot leads (score >= 70, open)
class Tolzar::DailyDigest
  HOT_SCORE = Tolzar::Briefing::HOT_SCORE

  def self.accounts
    ENV.fetch('TOLZAR_DIGEST_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def initialize(account, day: Date.current.yesterday)
    @account = account
    @range = day.in_time_zone('UTC').all_day
    @day = day
  end

  def report
    conversations = @account.conversations
    messages = Message.where(account_id: @account.id, created_at: @range)
    { 'workspace' => @account.name, 'day' => @day.iso8601,
      'new_conversations' => conversations.where(created_at: @range).count,
      'customer_messages' => messages.incoming.count,
      'team_replies' => messages.outgoing.where(private: false, sender_type: 'User').count,
      'resolved' => ReportingEvent.where(account_id: @account.id, name: 'conversation_resolved', created_at: @range).count,
      'open_now' => conversations.open.count,
      'waiting_now' => conversations.open.unattended.count,
      'hot_now' => conversations.open.joins(:contact).where("#{Tolzar::Briefing::SCORE} >= :min", min: HOT_SCORE).count }
  end
end
