require 'rails_helper'

# Tolzar's own widget, phase 2 (round 4, c75): the embed code Tolzar shows (inbox setup, settings) is our loader's
# snippet for workspaces on our own widget, and the old snippet everywhere else. Websites that already embed the
# old snippet are not touched: the old /packs/js/sdk.js keeps working exactly as before.
RSpec.describe Channel::WebWidget do
  let(:account) { create(:account) }
  let(:widget) { create(:channel_widget, account: account) }

  it 'gives the old snippet while the workspace is not on our widget' do
    script = widget.web_widget_script
    expect(script).to include('/packs/js/sdk.js', 'window.tolzarSDK.run', widget.website_token)
    expect(script).not_to include('/tz/widget.js')
  end

  it "gives our loader's snippet for a workspace on our own widget" do
    with_modified_env(TOLZAR_OWN_WIDGET_ACCOUNTS: account.id.to_s) do
      script = widget.web_widget_script
      expect(script).to include('/tz/widget.js', 'window.tolzar.run', widget.website_token)
      expect(script).not_to include('/packs/js/sdk.js')
    end
    expect(Rails.public_path.join('tz/widget.js')).to exist
  end
end
