# Tolzar feature board: per-user hourly limits (community plan §2): 5 posts (ideas and comments together) and
# 30 votes. A Redis counter per user and kind, expiring an hour after the first action of the window.
# Per-IP limits sit at the proxy, not here.
module Tolzar::FeedbackRateLimit
  LIMITS = { post: 5, vote: 30 }.freeze
  WINDOW = 1.hour

  # Counts this action; true when it goes over the user's limit for the current window.
  def self.exceeded?(kind, user_id)
    key = "tolzar:feedback:#{kind}:#{user_id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, WINDOW.to_i) if count == 1
    count > LIMITS.fetch(kind)
  end
end
