require 'rails_helper'

# Round 1 brain features through the admin proxy: allow-list, Owner-only writes, account isolation.
RSpec.describe 'Tolzar API round 1', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:role) { 'owner' }
  let(:gets) { [] }
  let(:posts) { [] }

  # Every brain call is recorded (one controller instance per request, so no any_instance expectations).
  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      { 'ok' => true, 'role' => role }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true }
    end
  end

  def brain_url(feature)
    "/api/v1/accounts/#{account.id}/tolzar/brain/#{feature}"
  end

  describe 'allow-list' do
    it 'reads every round 1 feature from its brain path, scoped to this workspace' do
      {
        'compliance' => '/compliance', 'retention' => '/retention', 'sms' => '/sms', 'crm_sync' => '/crm-sync',
        'crm_sync_runs' => '/crm-sync/runs', 'commerce' => '/commerce', 'commerce_templates' => '/commerce/templates',
        'negotiation' => '/negotiation', 'agent_teams' => '/agent-teams', 'tuning' => '/tuning', 'roi' => '/roi',
        'quotas' => '/quotas'
      }.each do |feature, path|
        get brain_url(feature), headers: admin.create_new_auth_token
        expect(response).to have_http_status(:success)
        expect(gets.last).to eq("#{path}?account_id=#{account.id}")
      end
    end

    it 'posts every round 1 feature to its brain path' do
      {
        'compliance' => '/compliance', 'retention' => '/retention', 'dsar_delete' => '/dsar/delete', 'sms' => '/sms',
        'sms_preview' => '/sms/preview', 'crm_sync' => '/crm-sync', 'crm_sync_preview' => '/crm-sync/preview',
        'commerce' => '/commerce', 'commerce_catalogue_sync' => '/commerce/catalogue-sync',
        'commerce_order_status' => '/commerce/order-status', 'negotiation' => '/negotiation',
        'agent_teams' => '/agent-teams', 'tuning_run' => '/tuning/run', 'tuning_decide' => '/tuning/decide',
        'quotas' => '/quotas'
      }.each do |feature, path|
        post brain_url(feature), params: {}, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(posts.last).to eq([path, { 'account_id' => account.id }])
      end
    end

    it 'refuses features that are not on the list' do
      get brain_url('kv'), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      post brain_url('dsar/delete'), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses agents' do
      get brain_url('roi'), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'owner-only' do
    let(:role) { 'manager' }
    # The account owner (H3) is always an Owner: `admin` is a second administrator here.
    let!(:account_owner) { create(:user, account: account, role: :administrator) }

    it 'refuses every settings write and the contact delete for a Manager' do
      %w[compliance retention dsar_delete sms crm_sync commerce commerce_catalogue_sync negotiation agent_teams
         tuning_decide quotas].each do |feature|
        post brain_url(feature), params: {}, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden), feature
        expect(response.parsed_body['error']).to eq('owner_only')
      end
      expect(posts).to be_empty
    end

    it 'refuses a contact data export for a Manager' do
      get brain_url('dsar_export'), params: { contact_id: 5 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end

    it 'still lets a Manager read settings and run previews' do
      get brain_url('quotas'), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      %w[sms_preview crm_sync_preview commerce_order_status tuning_run].each do |feature|
        post brain_url(feature), params: {}, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success), feature
      end
    end
  end

  describe 'account isolation' do
    it 'sends the URL workspace to the brain, never an account id from the body' do
      post brain_url('dsar_delete'), params: { contact_id: 7, account_id: other_account.id },
                                     headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts).to eq([['/dsar/delete', { 'contact_id' => 7, 'account_id' => account.id }]])
    end

    it 'scopes a contact export to this workspace' do
      get brain_url('dsar_export'), params: { contact_id: 7, account_id: other_account.id }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets.last).to eq("/dsar/export?account_id=#{account.id}&contact_id=7")
    end

    it "refuses another workspace's URL" do
      get "/api/v1/accounts/#{other_account.id}/tolzar/brain/roi", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/accounts/#{other_account.id}/tolzar/brain/quotas", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(posts).to be_empty
    end
  end
end
