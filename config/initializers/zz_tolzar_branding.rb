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
      # Every "Powered by" / legal link points at Tolzar's own address (TOLZAR_PUBLIC_URL), never
      # Chatwoot's site: the widget footer (WIDGET_BRAND_URL), e-mails (BRAND_URL), sign-up terms/privacy.
      # The domain is one switch: TOLZAR_PUBLIC_URL, else FRONTEND_URL (deploy/ops/DOMAIN-SWITCH.md).
      base = (ENV['TOLZAR_PUBLIC_URL'].presence || ENV['FRONTEND_URL'].presence).to_s.chomp('/')
      links = %w[BRAND_URL WIDGET_BRAND_URL TERMS_URL PRIVACY_URL]
      {
        'INSTALLATION_NAME' => 'Tolzar',
        'BRAND_NAME' => 'Tolzar',
        'BRAND_URL' => base,
        'WIDGET_BRAND_URL' => base,
        'TERMS_URL' => base,
        'PRIVACY_URL' => base,
        'CAPTAIN_TOOLS_CATALOG_URL' => ''            # never fetched from Chatwoot (Captain unused)
      }.each do |name, value|
        # No address configured: leave the links alone. (CAPTAIN_TOOLS_CATALOG_URL is blanked on purpose.)
        next if value.blank? && links.include?(name)
        config = InstallationConfig.find_by(name: name)
        config.update!(value: value) if config && config.value != value
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[Tolzar] branding init skipped: #{e.message}")
  end
end
