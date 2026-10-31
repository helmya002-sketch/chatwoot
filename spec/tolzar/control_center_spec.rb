require 'rails_helper'

# Tolzar Control Center pages (overview + alerts + funnel, workspaces, people & 2FA, system health): read-only,
# super admins only, and no billing row is created by looking.
RSpec.describe 'Tolzar Control Center', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Nile Bikes') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Mona Admin') }

  before do
    Rails.cache.clear
    # A new account already has its billing row (created with the account): set it, never insert a second.
    Tolzar::Subscription.find_or_initialize_by(account: account).update!(plan: 'trial', trial_ends_at: 3.days.from_now, seat_limit: 5)
  end

  it 'needs a super admin session' do
    get '/super_admin/control_center'
    expect(response).to have_http_status(:redirect)
  end

  describe 'with a super admin' do
    before do
      sign_in(super_admin, scope: :super_admin)
      # The brain is not running in specs: by default it answers like a brain that is down or restarting.
      allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 })
    end

    it 'shows the overview with alerts, a trial ending soon and the funnel' do
      expect { get '/super_admin/control_center' }.not_to change(Tolzar::Subscription, :count)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Trials ending in the next 7 days', 'Nile Bikes', 'Onboarding funnel')
      expect(response.body).to include('super admin') # the 2FA alert: the signed-in super admin has none
    end

    it 'lists and filters workspaces, and shows one' do
      get '/super_admin/control_center/workspaces', params: { q: 'Nile', state: 'trialing' }
      expect(response.body).to include('Nile Bikes')
      get '/super_admin/control_center/workspaces', params: { state: 'paused' }
      expect(response.body).not_to include('Nile Bikes')
      get "/super_admin/control_center/workspaces/#{account.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Mona Admin', 'Plan and limits')
    end

    it 'still shows a workspace when the brain is down, with the AI marked unavailable' do
      get "/super_admin/control_center/workspaces/#{account.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('The brain did not answer for this workspace.')
    end

    it "shows the workspace's AI as the brain sees it: kill switch, inbox modes, agents" do
      inbox = create(:inbox, account: account, name: 'Front desk mail')
      allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 })
      allow(Tolzar::BrainClient).to receive(:get).with('/audit?limit=50', account_id: account.id).and_return(
        { 'status' => 200, 'entries' => [{ 'at' => '2026-10-31T09:00:00Z', 'actor' => '3:owner@example.com', 'action' => 'workspace.kill_switch' }] }
      )
      allow(Tolzar::BrainClient).to receive(:get).with('/workspace/settings', account_id: account.id).and_return(
        { 'status' => 200, 'kill_switch_on' => false, 'inbox_modes' => { inbox.id.to_s => { 'mode' => 'live' } } }
      )
      allow(Tolzar::BrainClient).to receive(:get).with('/agents', account_id: account.id).and_return(
        { 'status' => 200, 'agents' => [{ 'name' => 'Sales agent', 'status' => 'active' }] }
      )
      get "/super_admin/control_center/workspaces/#{account.id}"
      expect(response.body).to include('Front desk mail', 'Live', 'Sales agent · active')
      expect(response.body).to include('workspace.kill_switch', '3:owner@example.com')
    end

    it 'lists people with administrators without 2FA first' do
      create(:user, account: account, role: :agent, name: 'Zed Agent')
      get '/super_admin/control_center/people', params: { missing: '1' }
      expect(response).to have_http_status(:success)
      body = response.body
      expect(body.index('Mona Admin')).to be < body.index('Zed Agent')
    end

    it 'shows system health with a backup status file' do
      file = Rails.root.join('tmp', "backup-status-#{SecureRandom.hex(4)}.json")
      File.write(file, { last_run: 30.hours.ago.iso8601, last_restore_test: 3.days.ago.iso8601, ok: true }.to_json)
      with_modified_env(TOLZAR_BACKUP_STATUS_FILE: file.to_s, TOLZAR_RELEASE: 'c21-test') do
        get '/super_admin/control_center/health'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('c21-test', 'Last backup', 'Check')
        expect(Tolzar::ControlCenter.new.alerts.pluck(:key)).to include('backup_old')
      end
    ensure
      FileUtils.rm_f(file)
    end
  end

  describe 'announcement banners (TOLZAR_ANNOUNCEMENTS)' do
    it 'stays closed while the switch is off and opens with it (the dashboard sees no banner until then)' do
      expect(Tolzar::Announcements.enabled?).to be(false)
      expect(DashboardController.new.send(:active_platform_banners)).to eq([])
      with_modified_env(TOLZAR_ANNOUNCEMENTS: 'true') do
        expect(Tolzar::Announcements.enabled?).to be(true)
        expect(DashboardController.new.send(:active_platform_banners)).to be_an(Array)
      end
    end
  end

  describe Tolzar::ControlCenter do
    it 'counts the funnel steps in order' do
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      steps = described_class.new.funnel.to_h
      expect(steps.values_at('signed_up', 'channel', 'first_message')).to all(be >= 1)
      expect(steps['first_reply']).to be <= steps['first_message']
    end

    it 'reads a missing or broken backup file as unknown, never as an alert' do
      with_modified_env(TOLZAR_BACKUP_STATUS_FILE: '/nonexistent/backup.json') do
        expect(described_class.new.backup_status).to eq(known: false)
        expect(described_class.new.alerts.pluck(:key)).not_to include('backup_old')
      end
    end
  end
end

RSpec.describe 'Tolzar Control Center AI safety and billing', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Nile Bikes') }

  before do
    Rails.cache.clear
    sign_in(super_admin, scope: :super_admin)
  end

  it 'shows each workspace kill switch and live inboxes as the brain reports them' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 })
    allow(Tolzar::BrainClient).to receive(:get).with('/workspace/settings', account_id: account.id).and_return(
      { 'status' => 200, 'kill_switch_on' => true, 'inbox_modes' => { '4' => { 'mode' => 'live' } } }
    )
    allow(Tolzar::BrainClient).to receive(:get).with('/agents', account_id: account.id).and_return({ 'status' => 200, 'agents' => [] })
    get '/super_admin/control_center/ai'
    expect(response).to have_http_status(:success)
    row = Tolzar::ControlCenter.new.ai_overview.find { |r| r[:id] == account.id }
    expect(row).to include(known: true, kill_switch_on: true, live_inboxes: 1)
    expect(response.body).to include('Nile Bikes', 'every inbox held in shadow')
  end

  it 'summarises plans, currencies, renewals and trials due' do
    Tolzar::Subscription.find_or_initialize_by(account: account).update!(plan: 'team', paid_until: 5.days.from_now, seat_limit: 5, currency: 'EGP')
    get '/super_admin/control_center/billing'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('Paid until, next 14 days', 'Nile Bikes', 'EGP')
    overview = Tolzar::ControlCenter.new.billing_overview
    expect(overview[:plans]).to eq('team' => 1)
    expect(overview[:renewals].first).to include(id: account.id, plan: 'team')
  end
end
