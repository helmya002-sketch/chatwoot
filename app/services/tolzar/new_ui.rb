# Tolzar app UI redesign (TOLZAR-APP-UI-REDESIGN-PLAN-2026-10-31.md): the new look is shown only for the
# workspaces listed in TOLZAR_NEW_UI_ACCOUNTS ("5,7"; empty by default = today's look everywhere). The account
# JSON carries `tolzar_new_ui`; the dashboard then sets `body.tz-ui` (assets/scss/_tolzar-ui.scss).
module Tolzar::NewUi
  module_function

  def accounts
    ENV.fetch('TOLZAR_NEW_UI_ACCOUNTS', '').split(',').filter_map { |id| Integer(id.strip, exception: false) }.select(&:positive?)
  end

  def enabled_for?(account_id)
    accounts.include?(account_id.to_i)
  end
end
