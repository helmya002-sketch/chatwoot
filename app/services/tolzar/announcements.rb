# Tolzar Control Center: the announcement banner to every workspace (maintenance, release notes), using the app's
# platform banners, which upstream opens only on its own cloud. TOLZAR_ANNOUNCEMENTS=true opens them here: super
# admins write banners in the console, the dashboard shows the active ones. Off by default, so nothing appears.
module Tolzar::Announcements
  module_function

  def enabled?
    ChatwootApp.chatwoot_cloud? || ActiveModel::Type::Boolean.new.cast(ENV.fetch('TOLZAR_ANNOUNCEMENTS', '').presence) == true
  end
end
