# frozen_string_literal: true

# Tolzar: routes one verified webhook body of a workspace's own Meta app (Tolzar::MetaHookController)
# to that workspace's listen-only Facebook Page inboxes, and only those. Messenger and Instagram DMs
# go to Chatwoot's own parsers (the same jobs its webhooks use); page and Instagram comments go to
# Tolzar::MetaCommentIngestService. Events for a page or account this workspace has not connected are
# dropped. `standby` entries (sent while another app, e.g. Business Suite, is the page's responder)
# are read like `messaging`.
class Tolzar::MetaHookRouter
  def initialize(app, body)
    @account = app.account
    @body = body.is_a?(Hash) ? body : {}
  end

  def perform
    Array(@body['entry']).each do |entry|
      next unless entry.is_a?(Hash)

      case @body['object']
      when 'page' then page_entry(entry)
      when 'instagram' then instagram_entry(entry)
      end
    end
  end

  private

  def page_entry(entry)
    channel = listen_only_pages.find_by(page_id: entry['id'].to_s)
    return if channel.blank?

    { 'messaging' => entry['messaging'], 'standby' => entry['standby'] }.each do |key, items|
      Array(items).each { |item| Webhooks::FacebookEventsJob.perform_later({ key => item }.to_json) if item.is_a?(Hash) }
    end
    changes(entry, 'feed').each { |value| comment(channel, 'facebook', value) }
  end

  def instagram_entry(entry)
    channel = listen_only_pages.find_by(instagram_id: entry['id'].to_s)
    return if channel.blank?

    Webhooks::InstagramEventsJob.perform_later([entry]) if entry['messaging'].present? || entry['standby'].present?
    changes(entry, 'comments').each { |value| comment(channel, 'instagram', value) }
  end

  def changes(entry, field)
    Array(entry['changes']).select { |c| c.is_a?(Hash) && c['field'] == field && c['value'].is_a?(Hash) }.pluck('value')
  end

  def comment(channel, platform, value)
    Tolzar::MetaCommentIngestService.new(channel: channel, platform: platform, value: value).perform
  rescue StandardError => e
    Rails.logger.warn("[Tolzar comments] #{platform} comment skipped: #{e.class}")
  end

  def listen_only_pages
    @account.facebook_pages.where(tolzar_listen_only: true)
  end
end
