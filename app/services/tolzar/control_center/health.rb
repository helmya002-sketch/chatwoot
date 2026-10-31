# Tolzar Control Center: system health (release, backups, the mirror, monitors, background queues). Read-only.
class Tolzar::ControlCenter::Health
  BACKUP_MAX_AGE = Tolzar::ControlCenter::BACKUP_MAX_AGE

  def initialize(now: Time.current)
    @now = now
  end

  def view
    {
      release: { app: ENV.fetch('TOLZAR_RELEASE', '').presence || GIT_HASH.to_s.first(9), git: GIT_HASH.to_s.first(12) },
      sidekiq: sidekiq,
      backup: backup_status,
      mirror_lag_seconds: mirror_lag,
      mirror_errors_24h: Tolzar::MirrorEvent.where(received_at: (@now - 24.hours)..).where.not(error: nil).count,
      monitors: monitors,
      mail: mail
    }
  end

  # TOLZAR_BACKUP_STATUS_FILE: a small JSON Server ops writes after each backup ({"last_run":ISO8601,
  # "last_restore_test":ISO8601,"ok":true}). Missing or unreadable: unknown, not an alert.
  def backup_status
    path = ENV.fetch('TOLZAR_BACKUP_STATUS_FILE', '').presence
    return { known: false } unless path && File.file?(path) && File.size(path) < 64.kilobytes

    data = JSON.parse(File.read(path))
    last = Time.zone.parse(data['last_run'].to_s)
    restore = Time.zone.parse(data['last_restore_test'].to_s) if data['last_restore_test'].present?
    age = last ? ((@now - last) / 1.hour).round(1) : nil
    { known: true, last_run: last, last_restore_test: restore, ok: data['ok'] == true, age_hours: age,
      stale: age.nil? || age > (BACKUP_MAX_AGE / 1.hour) || data['ok'] == false }
  rescue JSON::ParserError, ArgumentError, SystemCallError
    { known: false }
  end

  # Seconds since the newest mirror event arrived; nil when the mirror has never received one.
  def mirror_lag
    last = Tolzar::MirrorEvent.maximum(:received_at)
    last ? (@now - last).to_i : nil
  end

  # The newsletter's own sends in the last 24 hours, by outcome (Tolzar::NewsletterDelivery statuses).
  def mail
    rows = Tolzar::NewsletterDelivery.where(updated_at: (@now - 24.hours)..).group(:status).count
    { sent: rows.fetch('sent', 0), bounced: rows.fetch('bounced', 0), failed: rows.fetch('failed', 0) }
  rescue StandardError
    nil
  end

  private

  def sidekiq
    require 'sidekiq/api'
    queues = Sidekiq::Queue.all.map { |q| { name: q.name, size: q.size, latency: q.latency.round } }
    stats = Sidekiq::Stats.new
    { queues: queues, retries: stats.retry_size, dead: stats.dead_size, processes: Sidekiq::ProcessSet.new.size }
  rescue StandardError
    nil
  end

  # TOLZAR_KUMA_STATUS_URL: the monitoring status page's public JSON (Uptime Kuma /api/status-page/heartbeat/<slug>).
  # Fetched server-side with a short timeout and cached; nil when unset or unreachable.
  def monitors
    url = ENV.fetch('TOLZAR_KUMA_STATUS_URL', '').presence
    return unless url&.match?(%r{\Ahttps?://}i)

    Rails.cache.fetch("tolzar:control_center:kuma:#{Digest::SHA256.hexdigest(url)}", expires_in: 1.minute) do
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 3) do |http|
        http.get(uri.request_uri)
      end
      kuma_rows(res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil)
    end
  rescue StandardError
    nil
  end

  # {"heartbeatList": {"<id>": [{"status":1,"time":"…"}…]}} -> [{id:, up:, time:}]
  def kuma_rows(body)
    return unless body.is_a?(Hash) && body['heartbeatList'].is_a?(Hash)

    body['heartbeatList'].map do |id, beats|
      last = Array(beats).last || {}
      { id: id.to_s, up: last['status'].to_i == 1, time: last['time'].to_s }
    end
  end
end
