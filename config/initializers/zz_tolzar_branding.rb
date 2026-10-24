# frozen_string_literal: true

# Tolzar: brand this fork as "Tolzar". The Community super_admin branding UI
# gates INSTALLATION_NAME / BRAND_NAME / LOGO fields, but we own this MIT fork,
# so we set the installation/brand name directly in the DB config.
#
# InstallationConfig#after_commit clears the GlobalConfig Redis cache for us, so
# new page loads (Rails <title> + window.globalConfig) pick up "Tolzar".
#
# Fully guarded + idempotent so it can never break boot (there is no DB during
# asset precompile; it only writes when a value actually differs).
Rails.application.config.after_initialize do
  begin
    if ActiveRecord::Base.connection.table_exists?('installation_configs')
      {
        'INSTALLATION_NAME' => 'Tolzar',
        'BRAND_NAME' => 'Tolzar',
        'BRAND_URL' => 'https://chat.xplorer-redsea.com'
      }.each do |name, value|
        config = InstallationConfig.find_by(name: name)
        config.update!(value: value) if config && config.value != value
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[Tolzar] branding init skipped: #{e.message}")
  end
end
