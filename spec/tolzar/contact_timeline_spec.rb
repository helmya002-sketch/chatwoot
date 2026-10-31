require 'rails_helper'

# Tolzar contact timeline (round 4, c99): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; conversations follow the viewer's
# inbox access, newest first, with the win/loss reason; documents and bookings only while their switches are on.
RSpec.describe 'Tolzar contact timeline', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) do
    create(:contact, account: account,
                     custom_attributes: { tolzar_outcome_reason: 'won:price', tolzar_outcome_reason_at: 1.hour.ago.iso8601 })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/contacts/#{contact.id}/timeline" }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago)
    create(:conversation, account: account, inbox: other_inbox, contact: contact, created_at: 1.day.ago)
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'lists conversations and the reason, newest first, within the viewer access' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, headers: admin.create_new_auth_token
      events = response.parsed_body['events']
      expect(events.pluck('kind')).to eq(%w[outcome conversation conversation])
      expect(events.first).to include('outcome' => 'won', 'reason' => 'price')

      get url, headers: agent.create_new_auth_token
      expect(response.parsed_body['events'].pluck('kind')).to eq(%w[outcome conversation])
    end
  end
end
