require 'rails_helper'

# Workspace settings in the brain's DB, per-agent price sources, go-live and the kill switch through
# the proxy: Owner-only writes, this workspace only, the account name injected server-side.
RSpec.describe 'Tolzar workspace settings, price source, go-live', type: :request do
  let(:account) { create(:account, name: 'Blue Reef') }
  let(:other_account) { create(:account, name: 'Other') }
  # The first administrator is the account owner (Tolzar::AccountOwner); the second is a Manager.
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: other_account) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:gets) { [] }
  let(:posts) { [] }
  let(:brain_reply) { { 'ok' => true } }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      path.start_with?('/roles') ? { 'ok' => true, 'roles' => {} } : { 'ok' => true, 'version' => 3, 'inbox_modes' => {} }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      brain_reply
    end
  end

  def url(path)
    "/api/v1/accounts/#{account.id}/tolzar/#{path}"
  end

  describe 'GET workspace/settings' do
    it 'reads this workspace only and says who is looking' do
      get url('workspace/settings'), params: { account_id: other_account.id }, headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets).to include("/workspace/settings?account_id=#{account.id}")
      expect(response.parsed_body).to include('version' => 3, 'viewer_role' => 'manager', 'account_name' => 'Blue Reef')

      get url('workspace/settings'), headers: owner.create_new_auth_token
      expect(response.parsed_body['viewer_role']).to eq('owner')
    end

    it 'refuses agents' do
      get url('workspace/settings'), headers: agent_user.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a member of another account' do
      outsider = create(:user, account: other_account, role: :administrator)
      get url('workspace/settings'), headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(gets).to be_empty
    end
  end

  describe 'POST workspace/settings' do
    let(:change) { { version: 3, set: { 'working_hours.start' => '08:00', 'languages' => %w[en de] }, unset: ['timezone'] } }

    it 'is Owner-only' do
      post url('workspace/settings'), params: change, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('owner_only')
      expect(posts).to be_empty
    end

    it 'forwards only version, set and unset, with this workspace id' do
      post url('workspace/settings'), params: change.merge(account_id: other_account.id, inbox_modes: { '1' => 'live' }),
                                      headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      path, body = posts.last
      expect(path).to eq('/workspace/settings')
      expect(body[:account_id]).to eq(account.id)
      expect(body[:version]).to eq(3)
      expect(body[:set].to_h).to eq('working_hours.start' => '08:00', 'languages' => %w[en de])
      expect(body[:unset]).to eq(['timezone'])
      expect(body.keys).to contain_exactly(:account_id, :version, :set, :unset)
    end

    context 'when the brain refuses' do
      let(:brain_reply) { { 'ok' => false, 'error' => 'version_conflict', 'version' => 4 } }

      it 'keeps the conflict status' do
        post url('workspace/settings'), params: change, headers: owner.create_new_auth_token, as: :json
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['version']).to eq(4)
      end
    end

    context 'with invalid values' do
      let(:brain_reply) { { 'ok' => false, 'error' => 'invalid_settings', 'errors' => [{ 'path' => 'timezone', 'error' => 'x' }] } }

      it 'answers 400 with the field errors' do
        post url('workspace/settings'), params: change, headers: owner.create_new_auth_token, as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['errors'].first['path']).to eq('timezone')
      end
    end
  end

  describe 'price source' do
    it 'reads one agent of this workspace (every administrator)' do
      get url('agents/a1_b/price_source'), headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets.last).to eq("/agents/a1_b/price-source?account_id=#{account.id}")
    end

    # Pass 8: a test fetch can reach any https host, so it is Owner-only like the save.
    it 'refuses a Manager both the test fetch and the save' do
      post url('agents/a1/price_source/test'), params: { type: 'table', url: 'https://x.example/p.csv' },
                                                headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      post url('agents/a1/price_source'), params: { type: 'table', url: 'https://x.example/p.csv', refresh_hours: 24 },
                                           headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(posts).to be_empty
    end

    it 'lets the Owner test-fetch with only the allowed fields' do
      post url('agents/a1/price_source/test'), params: { type: 'table', url: 'https://x.example/p.csv' },
                                                headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/agents/a1/price-source/test',
                                { account_id: account.id, type: 'table', url: 'https://x.example/p.csv' }])
    end

    it 'saves for the Owner with only the allowed fields' do
      post url('agents/a1/price_source'), params: { type: 'feed', url: 'https://x.example/f', refresh_hours: 6,
                                                    account_id: other_account.id, key_env: 'SECRET' },
                                           headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/agents/a1/price-source',
                                { account_id: account.id, type: 'feed', url: 'https://x.example/f', refresh_hours: 6 }])
    end

    it 'refuses an agent id that is not a plain id' do
      get url('agents/a%20b/price_source'), headers: owner.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(gets.grep(/price-source/)).to be_empty
    end
  end

  describe 'go-live' do
    it 'is Owner-only' do
      post url('workspace/go_live'), params: { inbox_id: inbox.id, mode: 'live', confirm: 'Blue Reef' },
                                     headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post url('workspace/kill_switch'), headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(posts).to be_empty
    end

    it 'injects the account name server-side, never the one from the browser' do
      post url('workspace/go_live'), params: { inbox_id: inbox.id, mode: 'live', confirm: 'Evil', account_name: 'Evil',
                                               account_id: other_account.id },
                                     headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/workspace/go-live', { account_id: account.id, inbox_id: inbox.id, mode: 'live',
                                                        confirm: 'Evil', account_name: 'Blue Reef' }])
    end

    it "refuses another account's inbox and an unknown mode" do
      post url('workspace/go_live'), params: { inbox_id: other_inbox.id, mode: 'live', confirm: 'Blue Reef' },
                                     headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      post url('workspace/go_live'), params: { inbox_id: inbox.id, mode: 'eval' }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(posts).to be_empty
    end

    context 'when the brain says the inbox is not ready' do
      let(:brain_reply) { { 'ok' => false, 'error' => 'not_live_ready', 'reasons' => ['no_price_table'] } }

      it 'answers 422 with the reasons' do
        post url('workspace/go_live'), params: { inbox_id: inbox.id, mode: 'live', confirm: 'Blue Reef' },
                                       headers: owner.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['reasons']).to eq(['no_price_table'])
      end
    end

    it 'sends the kill switch for this workspace only' do
      post url('workspace/kill_switch'), params: { account_id: other_account.id }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/workspace/kill-switch', { account_id: account.id }])
    end
  end
end
