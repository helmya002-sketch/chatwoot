class Internal::CheckNewVersionsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Tolzar (round 4, c69): the newest version comes from our own release feed (TOLZAR_RELEASE_FEED_URL, JSON with a
  # "version"), never from Chatwoot's hub. No feed set: nothing is checked and no update notice is shown.
  FEED_TIMEOUT = 5

  def perform
    return unless Rails.env.production?

    @instance_info = tolzar_release_info
    update_version_info
  end

  def tolzar_release_info
    url = ENV.fetch('TOLZAR_RELEASE_FEED_URL', '').to_s.strip
    return nil unless url.start_with?('https://')

    body = nil
    SafeFetch.fetch(url, max_bytes: 64.kilobytes, open_timeout: FEED_TIMEOUT, read_timeout: FEED_TIMEOUT,
                         allowed_content_types: ['application/json'], allowed_content_type_prefixes: []) do |result|
      body = result.tempfile.read
    end
    info = JSON.parse(body.to_s)
    info.is_a?(Hash) && info['version'].to_s.match?(/\A\d+\.\d+\.\d+\z/) ? info : nil
  rescue StandardError => e
    Rails.logger.warn("[Tolzar] release feed not read (#{e.class})")
    nil
  end

  private

  def update_version_info
    return if @instance_info.blank? || @instance_info['version'].blank?   # no hub answer (telemetry off or unreachable)

    ::Redis::Alfred.set(::Redis::Alfred::LATEST_CHATWOOT_VERSION, @instance_info['version'])
  end
end

Internal::CheckNewVersionsJob.prepend_mod_with('Internal::CheckNewVersionsJob')
