require 'rails_helper'

# Tolzar saved-reply starter set (round 4, c93): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; adds only the
# missing short codes, so running it twice changes nothing and a business's own edits stay.
RSpec.describe 'Tolzar canned starters', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/canned_starters" }

  it 'is 404 while the switch is off' do
    post url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'adds the missing replies for administrators only, and keeps existing ones' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      account.canned_responses.create!(short_code: 'hello', content: 'Our own hello')
      post url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      post url, headers: admin.create_new_auth_token
      expect(response.parsed_body['added']).to eq(Tolzar::CannedStarters::SET.keys - ['hello'])
      expect(account.canned_responses.find_by(short_code: 'hello').content).to eq('Our own hello')

      post url, headers: admin.create_new_auth_token
      expect(response.parsed_body['added']).to eq([])
    end
  end
end
