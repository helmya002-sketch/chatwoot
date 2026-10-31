# Tolzar Control Center pages (phase 6): overview with alerts and the onboarding funnel, workspaces, people and 2FA,
# system health. Read-only; changes stay on their own pages (billing, accounts, users), which are audited.
class SuperAdmin::TolzarControlCenterController < SuperAdmin::ApplicationController
  def overview
    @overview = center.overview
    @alerts = center.alerts
    @funnel = center.funnel
  end

  def workspaces
    @query = params[:q].to_s.strip.first(100)
    @state = params[:state].to_s.presence_in(Tolzar::ControlCenter::STATES + ['none'])
    @rows = center.workspaces(query: @query, state: @state)
  end

  def workspace
    @account = Account.find(params[:id])
    @detail = center.workspace(@account)
  end

  def people
    @only_missing = params[:missing] == '1'
    @rows = center.people(only_missing: @only_missing)
  end

  def health
    @health = center.health
  end

  private

  def center
    @center ||= Tolzar::ControlCenter.new
  end
end
