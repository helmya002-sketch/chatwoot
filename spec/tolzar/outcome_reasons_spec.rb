require 'rails_helper'

# Tolzar win/loss reasons (round 4, c95): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; counts the reasons
# picked within the period and ignores malformed or older ones.
RSpec.describe 'Tolzar outcome reasons', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/outcome_reasons" }

  def contact_with(reason, at)
    create(:contact, account: account,
                     custom_attributes: { tolzar_outcome_reason: reason, tolzar_outcome_reason_at: at&.iso8601 })
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'counts recent, well-formed reasons for administrators only' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      2.times { contact_with('won:price', 2.days.ago) }
      contact_with('lost:no_reply', 3.days.ago)
      contact_with('lost:no_reply', 40.days.ago)
      contact_with('maybe:price', 1.day.ago)
      contact_with('won:price', nil)
      create(:contact, account: account)

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, params: { days: 30 }, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['days']).to eq(30)
      expect(body['reasons']).to eq([{ 'outcome' => 'lost', 'reason' => 'no_reply', 'count' => 1 },
                                     { 'outcome' => 'won', 'reason' => 'price', 'count' => 2 }])

      get url, params: { days: 90 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['reasons'].first['count']).to eq(2)

      get url, params: { days: 5000 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['days']).to eq(30)
    end
  end
end
