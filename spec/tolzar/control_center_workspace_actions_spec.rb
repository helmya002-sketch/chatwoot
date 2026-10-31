require 'rails_helper'

# Tolzar Control Center: pause / resume a workspace (typed name + reason, audited with the reason; a hold never
# schedules a purge), switch-change requests (closed before 12 Nov, never a secret), mail health.
RSpec.describe 'Tolzar Control Center workspace actions', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Nile Bikes') }

  before do
    sign_in(super_admin, scope: :super_admin)
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 })
  end

  it 'pauses only with the typed name and a reason, never with a purge date, and resumes' do
    post "/super_admin/control_center/workspaces/#{account.id}/hold", params: { confirm: 'Nile', reason: 'chargeback dispute' }
    expect(Tolzar::Subscription.for(account).reload.held_at).to be_nil

    post "/super_admin/control_center/workspaces/#{account.id}/hold", params: { confirm: 'Nile Bikes', reason: 'chargeback dispute' }
    sub = Tolzar::Subscription.for(account).reload
    expect(sub.state).to eq('paused')
    expect(sub.purge_after).to be_nil
    expect(Tolzar::SuperAdminAudit.recent.first).to have_attributes(action: 'hold', note: 'chargeback dispute', record_id: account.id.to_s)
    get "/super_admin/control_center/workspaces/#{account.id}"
    expect(response.body).to include('Paused since', 'chargeback dispute', 'Resume workspace')

    post "/super_admin/control_center/workspaces/#{account.id}/release", params: { confirm: 'Nile Bikes', reason: 'dispute settled' }
    expect(Tolzar::Subscription.for(account).reload.held_at).to be_nil
  end

  it 'keeps switch-change requests closed before 12 Nov and refuses secrets after' do
    travel_to(Date.new(2026, 11, 1)) do
      post '/super_admin/tolzar_switch_requests', params: { name: 'TOLZAR_DEMO', value: 'on', reason: 'ws5 demo test' }
      expect(Tolzar::SuperAdminAudit.where(action: 'switch_change_request')).to be_empty
    end
    travel_to(Date.new(2026, 11, 13)) do
      post '/super_admin/tolzar_switch_requests', params: { name: 'TOLZAR_BRAIN_SECRET', value: 'x', reason: 'should not pass' }
      expect(Tolzar::SuperAdminAudit.where(action: 'switch_change_request')).to be_empty
      post '/super_admin/tolzar_switch_requests', params: { name: 'TOLZAR_DEMO', value: 'on', reason: 'ws5 demo test' }
      expect(Tolzar::SuperAdminAudit.where(action: 'switch_change_request').sole.note).to eq('TOLZAR_DEMO=on · ws5 demo test')
    end
  end

  it 'shows mail health and the XPay state' do
    get '/super_admin/control_center/health'
    expect(response.body).to include('Mail (newsletter, last 24 hours)')
    get '/super_admin/control_center/billing'
    expect(response.body).to include('XPay checkout: not connected yet')
  end
end
