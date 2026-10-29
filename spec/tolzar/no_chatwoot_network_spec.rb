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

  # Round "our docs": no link to Chatwoot's site anywhere a user can see it, languages included.
  # Any mention: links, e-mail addresses, bare domains, comments (the image scan counts them all).
  it 'has no chatwoot.com address in app, lib or config (languages included)' do
    any_host = /chatwoot\.(?:com|dev|help)\b/i
    files = Dir.glob(Rails.root.join('{app,lib,config}/**/*.{rb,js,vue,yml,erb,liquid,json,scss}').to_s)
               .reject { |f| f =~ %r{(\.spec\.js|\.story\.vue|_spec\.rb|/fixtures\.js)$} || f =~ %r{/(specs?|fixtures|story|stories)/} }
    offenders = files.select { |f| File.read(f).match?(any_host) }
    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to eq([])
  end

  it 'does not relay mobile push through Chatwoot by default' do
    with_modified_env ENABLE_PUSH_RELAY_SERVER: nil do
      # The switch reads only the env, so no notification (and no factory chain) is needed.
      [Notification::PushNotificationService, Notification::PushTestService].each do |klass|
        expect(klass.allocate.send(:chatwoot_hub_enabled?)).to be(false)
      end
    end
  end
end
