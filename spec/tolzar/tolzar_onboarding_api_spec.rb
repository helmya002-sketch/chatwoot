require 'rails_helper'

# First-run setup through the proxy (brain plugins/onboarding.py): the bootstrap is Owner-only and
# carries this account's owner from the server side; the checklist is for every administrator.
RSpec.describe 'Tolzar workspace bootstrap and checklist', type: :request do
  let(:account) { create(:account, name: 'Blue Reef') }
  let(:other_account) { create(:account, name: 'Other') }
  # The first administrator is the account owner (Tolzar::AccountOwner); the second is a Manager.
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:gets) { [] }
  let(:posts) { [] }
  let(:brain_reply) { { 'ok' => true, 'version' => 1, 'agent' => { 'id' => 'agent-1', 'status' => 'inactive' } } }
  let(:setup) do
    { workspace_name: 'Blue Reef', timezone: 'Africa/Cairo',
      working_hours: { start: '09:00', end: '18:00', closed_days: ['fri'] },
      languages: %w[en de], pack: 'none', template: 'tpl-support', agent_name: 'Mia' }
  end

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      if path.start_with?('/roles')
        { 'ok' => true, 'roles' => {} }
      else
        { 'ok' => true, 'done' => 1, 'total' => 7, 'items' => [{ 'key' => 'settings', 'done' => true }] }
      end
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      brain_reply
    end
  end

  def url(path)
    "/api/v1/accounts/#{account.id}/tolzar/#{path}"
  end

  describe 'POST workspace/bootstrap' do
    it 'is Owner-only' do
      post url('workspace/bootstrap'), params: setup, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('owner_only')

      post url('workspace/bootstrap'), params: setup, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(posts).to be_empty
    end

    it 'forwards the known fields with this workspace and the server-side owner' do
      post url('workspace/bootstrap'),
           params: setup.merge(owner_user_id: manager.id, account_id: other_account.id, status: 'active',
                               working_hours: setup[:working_hours].merge(holidays: ['x'])),
           headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      path, body = posts.last
      expect(path).to eq('/workspace/bootstrap')
      expect(body['account_id']).to eq(account.id)
      expect(body['owner_user_id']).to eq(owner.id)
      expect(body['working_hours']).to eq('start' => '09:00', 'end' => '18:00', 'closed_days' => ['fri'])
      expect(body.keys).to contain_exactly('workspace_name', 'timezone', 'working_hours', 'languages', 'pack',
                                           'template', 'agent_name', 'account_id', 'owner_user_id')
      expect(body['languages']).to eq(%w[en de])
      expect(response.parsed_body['agent']['status']).to eq('inactive')
    end

    it 'leaves out fields the page did not send' do
      post url('workspace/bootstrap'), params: { workspace_name: 'Blue Reef', timezone: 'UTC' },
                                       headers: owner.create_new_auth_token, as: :json
      expect(posts.last[1].keys).to contain_exactly('workspace_name', 'timezone', 'account_id', 'owner_user_id')
    end

    %w[already_bootstrapped settings_exist workspace_has_config_file].each do |code|
      context "when the brain refuses with #{code}" do
        let(:brain_reply) { { 'ok' => false, 'error' => code } }

        it 'answers 409' do
          post url('workspace/bootstrap'), params: setup, headers: owner.create_new_auth_token, as: :json
          expect(response).to have_http_status(:conflict)
          expect(response.parsed_body['error']).to eq(code)
        end
      end
    end

    context 'with invalid values' do
      let(:brain_reply) { { 'ok' => false, 'error' => 'invalid_settings', 'errors' => [{ 'path' => 'timezone', 'error' => 'x' }] } }

      it 'answers 400 with the field errors' do
        post url('workspace/bootstrap'), params: setup, headers: owner.create_new_auth_token, as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['errors'].first['path']).to eq('timezone')
      end
    end
  end

  describe 'GET workspace/checklist' do
    it 'is open to every administrator, for this workspace and its inboxes' do
      inbox = create(:inbox, account: account)
      create(:inbox, account: other_account)
      get url('workspace/checklist'), params: { account_id: other_account.id }, headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets.last).to eq("/workspace/checklist?account_id=#{account.id}&inbox_ids=#{inbox.id}")
      expect(response.parsed_body['total']).to eq(7)
    end

    it 'refuses agents and members of another account' do
      get url('workspace/checklist'), headers: agent_user.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      outsider = create(:user, account: other_account, role: :administrator)
      get url('workspace/checklist'), headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(gets.grep(%r{/workspace/checklist})).to be_empty
    end

    it 'tells the brain the account owner once when its Owner item is open' do
      open_item = { 'ok' => true, 'items' => [{ 'key' => 'owner', 'done' => false }] }
      allow_any_instance_of(controller_class).to receive(:get_from_brain) { |_c, path| (gets << path) && open_item }
      get url('workspace/checklist'), headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(posts).to eq([['/workspace/owner', { account_id: account.id, owner_user_id: owner.id }]])
      expect(gets.size).to eq(2)
    end

    it 'does not post when the Owner item is done' do
      get url('workspace/checklist'), headers: manager.create_new_auth_token
      expect(posts).to be_empty
    end
  end
end
