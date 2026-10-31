require 'rails_helper'

# The UI redesign is per workspace (TOLZAR_NEW_UI_ACCOUNTS, empty by default): nothing changes for anyone else.
RSpec.describe Tolzar::NewUi, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'is off for every workspace by default' do
    expect(described_class.enabled_for?(account.id)).to be(false)
  end

  it 'turns on only the listed workspaces and ignores bad entries' do
    with_modified_env(TOLZAR_NEW_UI_ACCOUNTS: " #{account.id}, x,0,-3") do
      expect(described_class.accounts).to eq([account.id])
      expect(described_class.enabled_for?(account.id)).to be(true)
      expect(described_class.enabled_for?(account.id + 1)).to be(false)
    end
  end

  it 'tells the dashboard through the account JSON' do
    with_modified_env(TOLZAR_NEW_UI_ACCOUNTS: account.id.to_s) do
      get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['tolzar_new_ui']).to be(true)
    end
    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['tolzar_new_ui']).to be(false)
  end
end
