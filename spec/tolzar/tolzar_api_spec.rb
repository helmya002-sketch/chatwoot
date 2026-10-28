require 'rails_helper'

# Tolzar admin API: admin-only, brain errors handled, export + audit work.
RSpec.describe 'Tolzar API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'entries' => [], 'role' => 'owner' })
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:post_to_brain).and_return({ 'ok' => true })
  end

  it 'refuses agents and answers admins' do
    get "/api/v1/accounts/#{account.id}/tolzar/workflows", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/accounts/#{account.id}/tolzar/workflows", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
  end

  it 'queues a workspace export and lists it' do
    expect do
      post "/api/v1/accounts/#{account.id}/tolzar/export", headers: admin.create_new_auth_token
    end.to have_enqueued_job(Tolzar::WorkspaceExportJob).with(account.id)

    get "/api/v1/accounts/#{account.id}/tolzar/export", headers: admin.create_new_auth_token
    expect(response.parsed_body['exports']).to eq([])
  end

  it 'lists admin changes in the audit log without secrets' do
    inbox = create(:inbox, account: account)
    inbox.update!(name: 'Renamed')

    get "/api/v1/accounts/#{account.id}/tolzar/audit", headers: admin.create_new_auth_token
    entries = response.parsed_body['entries']
    expect(entries.map { |e| e['action'] }).to include('inbox.update')
    expect(entries.to_json).not_to match(/token|password/i)
  end

  it 'lets only an Owner export the workspace (a Manager is refused)' do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'role' => 'manager' })
    post "/api/v1/accounts/#{account.id}/tolzar/export", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    post "/api/v1/accounts/#{account.id}/tolzar/brain/mcp_token", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'lets every member read the branding (and only the branding)' do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain)
      .and_return({ 'ok' => true, 'branding' => { 'product_name' => 'Bright Inbox', 'secret' => 'x' } })
    get "/api/v1/accounts/#{account.id}/tolzar/branding", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['branding']).to eq('product_name' => 'Bright Inbox')
  end
end
