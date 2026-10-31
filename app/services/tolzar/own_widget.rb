# Tolzar's own website widget, phase 1 (TOLZAR-OWN-WIDGET-AND-APP-PLAN-2026-10-31.md Part A): the iframe page
# /widget renders the Tolzar app (app/javascript/tolzar-widget) instead of the old one for the workspaces in
# TOLZAR_OWN_WIDGET_ACCOUNTS (comma-separated ids; empty = nobody, the old widget everywhere). Same controller,
# same visitor token and session, same loader on the customer's page; removing a workspace switches it back.
module Tolzar::OwnWidget
  module_function

  def accounts
    ENV.fetch('TOLZAR_OWN_WIDGET_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def on?(account_id)
    accounts.include?(account_id.to_i)
  end

  # What the app needs, as data (rendered into a JSON script tag, never into JS).
  def page_config(web_widget, contact_inbox, token)
    inbox = web_widget.inbox
    {
      authToken: token,
      maxFileMb: GlobalConfig.get('MAXIMUM_FILE_UPLOAD_SIZE')['MAXIMUM_FILE_UPLOAD_SIZE'],
      pubsubToken: contact_inbox&.pubsub_token,
      locale: web_widget.account.locale,
      channel: {
        websiteToken: web_widget.website_token, websiteName: inbox.name, widgetColor: web_widget.widget_color,
        welcomeTitle: web_widget.welcome_title, welcomeTagline: web_widget.welcome_tagline, replyTime: web_widget.reply_time,
        avatarUrl: inbox.avatar_url, locale: web_widget.account.locale,
        preChatFormEnabled: web_widget.pre_chat_form_enabled, preChatFormOptions: web_widget.pre_chat_form_options,
        workingHoursEnabled: inbox.working_hours_enabled, workingHours: inbox.working_hours,
        outOfOfficeMessage: inbox.out_of_office_message, timezone: inbox.timezone,
        allowMessagesAfterResolved: inbox.allow_messages_after_resolved,
        enabledFeatures: web_widget.selected_feature_flags
      }
    }
  end
end
