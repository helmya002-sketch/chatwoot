require 'rails_helper'

# H3: Owner-only must not mean admin-only. The account owner (first administrator, stored on the
# account) is always an Owner and can't be demoted or removed; other administrators are Managers
# unless an Owner promoted them; only an Owner changes roles; every settings/data write is Owner-only.
RSpec.describe 'Tolzar account owner (H3)', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:second_admin) { create(:user, account: account, role: :administrator) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  # What the brain answers today: its role table, plus the old default that calls every admin an Owner.
  let(:brain_roles) { {} }
  let(:posts) { [] }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, _path|
      { 'ok' => true, 'role' => 'owner', 'roles' => brain_roles }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true }
    end
  end

  def brain_url(feature)
    "/api/v1/accounts/#{account.id}/tolzar/brain/#{feature}"
  end

  it 'stores the first administrator as the account owner' do
    expect(Tolzar::AccountOwner.user_id(account)).to eq(owner.id)
    expect(account.reload.internal_attributes['tolzar_owner_user_id']).to eq(owner.id)
  end

  it "does not make another admin an Owner because the brain's default says so" do
    post brain_url('roles'), params: { user_id: owner.id, role: 'manager' }, headers: second_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('owner_only')
    expect(posts).to be_empty
  end

  it 'refuses every settings write (agents, knowledge, media, workflows, ...) for a Manager' do
    (controller_class::OWNER_POSTS & %w[media knowledge_refresh branding sla channels roles mcp_token]).each do |feature|
      post brain_url(feature), params: {}, headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden), feature
    end
    expect(controller_class::OWNER_POSTS).to include('media', 'knowledge_refresh', 'branding', 'sla', 'channels')
    %w[agents agents/delete agents/default workflows workflows/delete].each do |path|
      post "/api/v1/accounts/#{account.id}/tolzar/#{path}", params: {}, headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden), path
    end
    expect(posts).to be_empty
  end

  it 'still lets a Manager run tests and previews' do
    post brain_url('sms_preview'), params: {}, headers: second_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/tolzar/agent_test", params: { message: 'hi' }, headers: second_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'never takes the owner id from the browser' do
    post brain_url('roles'), params: { user_id: second_admin.id, role: 'owner', owner_user_id: second_admin.id },
                             headers: owner.create_new_auth_token, as: :json
    expect(posts.last[1]['owner_user_id']).to eq(owner.id)
  end

  it 'refuses demoting the account owner, even by the owner' do
    post brain_url('roles'), params: { user_id: owner.id, role: 'manager' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('account_owner_fixed')
    expect(posts).to be_empty
  end

  it 'lets the owner promote and demote another admin, and returns 422 for a non-member' do
    post brain_url('roles'), params: { user_id: second_admin.id, role: 'owner' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post brain_url('roles'), params: { user_id: second_admin.id, role: 'manager' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(posts.map(&:first)).to eq(%w[/roles /roles])
    # The owner id reaches the brain from the server, even if the browser sends another one.
    expect(posts.map { |_p, b| b['owner_user_id'] }).to eq([owner.id, owner.id])

    post brain_url('roles'), params: { user_id: create(:user).id, role: 'manager' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when the brain table promoted the second admin' do
    let(:brain_roles) { { second_admin.id.to_s => 'owner' } }

    it 'treats them as an Owner, who still cannot demote the account owner' do
      post brain_url('media'), params: {}, headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      post brain_url('roles'), params: { user_id: owner.id, role: 'agent' }, headers: second_admin.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq('account_owner_fixed')
    end
  end

  it 'shows the fixed account owner on the roles page' do
    get brain_url('roles'), headers: owner.create_new_auth_token
    expect(response.parsed_body['owner_user_id']).to eq(owner.id)
  end

  describe 'Chatwoot agents API' do
    it 'refuses demoting or removing the account owner' do
      put "/api/v1/accounts/#{account.id}/agents/#{owner.id}", params: { agent: { role: 'agent' } },
                                                               headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(owner.account_users.find_by(account: account)).to be_administrator

      delete "/api/v1/accounts/#{account.id}/agents/#{owner.id}", headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(account.account_users.exists?(user_id: owner.id)).to be(true)
    end

    it 'still lets admins rename the owner and change other members' do
      put "/api/v1/accounts/#{account.id}/agents/#{owner.id}", params: { agent: { name: 'Boss' } },
                                                               headers: second_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      put "/api/v1/accounts/#{account.id}/agents/#{second_admin.id}", params: { agent: { role: 'agent' } },
                                                                      headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
