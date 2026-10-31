# Tolzar own widget per-page analytics (round 3 c53): how often the chat is opened and a conversation started, per
# page path and day, per website inbox. Counters only (Redis hashes, 40 days), no visitor id, no query string: the
# page is origin + path as the widget sends it. Read by administrators (tolzar/widget_stats).
module Tolzar::WidgetStats
  KINDS = %w[open start].freeze
  DAYS_KEPT = 40
  MAX_PAGES = 200

  module_function

  def key(inbox_id, day, kind)
    "tolzar:widget_stats:#{inbox_id}:#{day.strftime('%Y%m%d')}:#{kind}"
  end

  def clean_page(page)
    uri = URI.parse(page.to_s)
    return unless %w[http https].include?(uri.scheme) && uri.host

    "#{uri.scheme}://#{uri.host}#{uri.path.presence || '/'}".first(300)
  rescue URI::InvalidURIError
    nil
  end

  def record(inbox_id, kind, page, day: Date.current)
    page = clean_page(page)
    return false unless KINDS.include?(kind.to_s) && page

    k = key(inbox_id, day, kind)
    $alfred.with do |conn|
      return false if conn.hlen(k) >= MAX_PAGES && !conn.hexists(k, page)

      conn.hincrby(k, page, 1)
      conn.expire(k, DAYS_KEPT.days.to_i)
    end
    true
  end

  # [{page:, open:, start:, rate:}] summed over the last `days` days, most opened first.
  def report(inbox_id, days: 30, today: Date.current)
    totals = Hash.new { |h, p| h[p] = { open: 0, start: 0 } }
    (0...days.clamp(1, DAYS_KEPT)).each do |i|
      day = today - i
      KINDS.each do |kind|
        ($alfred.with { |conn| conn.hgetall(key(inbox_id, day, kind)) } || {}).each do |page, n|
          totals[page][kind.to_sym] += n.to_i
        end
      end
    end
    totals.map { |page, c| { page: page, **c, rate: c[:open].positive? ? (100.0 * c[:start] / c[:open]).round : nil } }
          .sort_by { |r| -r[:open] }
  end
end
