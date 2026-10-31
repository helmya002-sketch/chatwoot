require 'rails_helper'

# Tolzar conversation summary on demand (round 4, E1; Shadow): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; only people who
# may see the conversation; the brain's summary goes back to the staff member and nothing is written or sent.
RSpec.describe 'Tolzar conversation summary', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/conversations/#{conversation.display_id}/summary" }

  it 'is 404 while the switch is off, and never calls the brain' do
    expect(Tolzar::BrainClient).not_to receive(:post)
    post url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'returns the brain summary to staff without writing a message' do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 200, 'summary' => '  Wants a quote for two.  ' })
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      expect { post url, headers: admin.create_new_auth_token }.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['summary']).to eq('Wants a quote for two.')
    end
    expect(Tolzar::BrainClient).to have_received(:post)
      .with('/summary', { account_id: account.id, conversation_id: conversation.display_id }, account_id: account.id)
  end

  it 'answers 502 politely when the brain fails or has nothing' do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 502, 'ok' => false, 'error' => 'brain_unreachable' })
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      post url, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['error']).to eq('brain_unavailable')
    end
  end

  it 'refuses an agent who cannot see the conversation' do
    allow(Tolzar::BrainClient).to receive(:post)
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      post url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
    expect(Tolzar::BrainClient).not_to have_received(:post)
  end
end
