require 'rails_helper'

# Tolzar Control Center pages (overview + alerts + funnel, workspaces, people & 2FA, system health): read-only,
# super admins only, and no billing row is created by looking.
RSpec.describe 'Tolzar Control Center', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Nile Bikes') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Mona Admin') }

  before do
    Rails.cache.clear
    Tolzar::Subscription.create!(account: account, plan: 'trial', trial_ends_at: 3.days.from_now, seat_limit: 5)
  end

  it 'needs a super admin session' do
    get '/super_admin/control_center'
    expect(response).to have_http_status(:redirect)
  end

  describe 'with a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

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
    before { sign_in(super_admin, scope: :super_admin) }

    it 'stays closed while the switch is off and opens with it' do
      get '/super_admin/platform_banners'
      expect(response).to have_http_status(:not_found)
      with_modified_env(TOLZAR_ANNOUNCEMENTS: 'true') do
        expect(Tolzar::Announcements.enabled?).to be(true)
        get '/super_admin/platform_banners'
        expect(response).to have_http_status(:success)
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
