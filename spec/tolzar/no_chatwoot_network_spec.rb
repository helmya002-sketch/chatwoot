require 'rails_helper'

# Tolzar guard (owner rule, 29 Oct 2026: never depend on Chatwoot the company): no code in app/, lib/ or
# config/ may name one of Chatwoot's service hosts (hub, CDN, status page, image CDN), and the push relay
# is off unless an install deliberately turns it on. Docs links are handled separately (help centre).
RSpec.describe 'No dependency on Chatwoot services' do
  let(:service_hosts) { /\b(?:hub\.\d*\.?chatwoot\.com|[a-z.]*cdn\.chatwoot\.com|status\.chatwoot\.com|images\.chatwoot\.com)\b/ }

  it 'names no Chatwoot service host in runtime code' do
    files = Dir.glob(Rails.root.join('{app,lib,config}/**/*.{rb,js,vue,yml,erb,liquid}').to_s)
               .reject { |f| f.include?('/i18n/') || f =~ /(\.spec\.js|\.story\.vue|_spec\.rb)$/ || f.include?('/specs/') }
    offenders = files.select { |f| File.read(f).match?(service_hosts) }
    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to eq([])
  end

  it 'does not relay mobile push through Chatwoot by default' do
    with_modified_env ENABLE_PUSH_RELAY_SERVER: nil do
      service = Notification::PushNotificationService.new(notification: build(:notification))
      expect(service.send(:chatwoot_hub_enabled?)).to be(false)
    end
  end
end
