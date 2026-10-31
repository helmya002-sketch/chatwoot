require 'rails_helper'

# Tolzar Results → Channels (round 4, c97): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; every inbox
# listed, conversations and customer messages counted within the period only.
RSpec.describe 'Tolzar channel breakdown', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:busy) { create(:inbox, account: account, name: 'Website') }
  let!(:quiet) { create(:inbox, account: account, name: 'Email') }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/channel_breakdown" }

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'counts per inbox within the period, for administrators only' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      conversation = create(:conversation, account: account, inbox: busy)
      create(:conversation, account: account, inbox: busy, created_at: 40.days.ago)
      create(:message, account: account, inbox: busy, conversation: conversation, message_type: :incoming)

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, headers: admin.create_new_auth_token
      rows = response.parsed_body['inboxes']
      expect(rows.pluck('name')).to eq(%w[Website Email])
      expect(rows.first).to include('conversations' => 1, 'incoming' => 1)
      expect(rows.last).to include('conversations' => 0, 'incoming' => 0, 'first_reply' => nil, 'resolved' => 0)
    end
  end
end
