# frozen_string_literal: true

# Connects a Facebook Page (and the Instagram account linked to it) to Tolzar in listen-only mode,
# through the workspace's own Meta app (Tolzar::MetaApp). The Owner pastes a token from the business's
# own Meta portfolio (a system user with the page). We read the page once, create the inbox with every
# customer-facing auto-message off, and subscribe our app to the page (Tolzar::MetaGraph). The page's
# settings, its other apps and Meta Business Suite are not touched; nothing is ever sent from it.
class Tolzar::MetaListenOnlySetupService
  attr_reader :channel, :inbox, :webhook_error

  def initialize(account:, page_id:, access_token:, inbox_name: nil)
    @account = account
    @page_id = page_id.to_s.strip
    @access_token = access_token.to_s.strip
    @inbox_name = inbox_name
  end

  def perform
    app = @account.tolzar_meta_app
    raise ArgumentError, 'Save the workspace Meta app first (app id and secret)' if app.blank?
    raise ArgumentError, 'The page id is the number from the page\'s About section' unless @page_id.match?(/\A\d{5,25}\z/)
    raise ArgumentError, 'The access token is required' if @access_token.blank?

    page = Tolzar::MetaGraph.page(@page_id, @access_token, app.app_secret)
    create_channel_and_inbox(page)
    subscribe(app)
    self
  end

  # Called when a listen-only page inbox is deleted: only our app's subscription goes, and only when
  # no other inbox of this workspace still uses the page (Chatwoot keeps one per page and account).
  def self.teardown(channel)
    app = Tolzar::MetaApp.find_by(account_id: channel.account_id)
    return if app.blank?

    Tolzar::MetaGraph.unsubscribe(channel.page_id, channel.page_access_token, app.app_secret)
  rescue Tolzar::MetaGraph::Error => e
    Rails.logger.warn("[Tolzar listen-only] could not unsubscribe page #{channel.page_id}: #{e.message}")
  end

  private

  def create_channel_and_inbox(page)
    token = page['access_token'].presence || @access_token
    ActiveRecord::Base.transaction do
      @channel = @account.facebook_pages.create!(
        page_id: page['id'], page_access_token: token, user_access_token: @access_token,
        instagram_id: page.dig('instagram_business_account', 'id'), tolzar_listen_only: true
      )
      @inbox = @account.inboxes.create!(
        name: @inbox_name.to_s.strip.presence || "#{page['name']} (listen-only)",
        channel: @channel,
        greeting_enabled: false, working_hours_enabled: false, csat_survey_enabled: false, enable_email_collect: false
      )
    end
  end

  def subscribe(app)
    Tolzar::MetaGraph.subscribe(@channel.page_id, @channel.page_access_token, app.app_secret)
  rescue Tolzar::MetaGraph::Error => e
    @webhook_error = e.message
  end
end
