require 'rails_helper'

# Readiness gap 22: a Manager (an administrator who is not the Owner) cannot use Chatwoot's admin actions
# outside Tolzar's screens: delete inboxes, reset bot tokens, webhooks, integrations, promote admins,
# remove members, change the workspace settings. The Owner can.
RSpec.describe 'Tolzar Manager gate', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }

  before do
    Tolzar::AccountOwner.user_id(account)
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true, 'roles' => {} })
    Rails.cache.clear
  end

  it 'refuses a Manager deleting an inbox, and lets the Owner' do
    delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: manager.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('owner_only')
    expect(Inbox.exists?(inbox.id)).to be(true)

    delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: owner.create_new_auth_token
    expect(response).to have_http_status(:success)
  end

  it 'refuses a Manager webhooks and making someone an administrator, but not inviting an agent' do
    post "/api/v1/accounts/#{account.id}/webhooks", params: { webhook: { url: 'https://example.com/h', subscriptions: ['message_created'] } },
                                                    headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/accounts/#{account.id}/agents", params: { name: 'A', email: 'a1@example.com', role: 'administrator' },
                                                  headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/accounts/#{account.id}/agents", params: { name: 'B', email: 'b1@example.com', role: 'agent' },
                                                  headers: manager.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:forbidden)
  end

  it 'refuses a Manager changing the workspace settings' do
    patch "/api/v1/accounts/#{account.id}", params: { name: 'Renamed' }, headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(account.reload.name).not_to eq('Renamed')
  end

  it 'treats an administrator the brain marks owner as an Owner' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true, 'roles' => { manager.id.to_s => 'owner' } })
    delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: manager.create_new_auth_token
    expect(response).to have_http_status(:success)
  end
end
