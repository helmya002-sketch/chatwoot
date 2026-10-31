require 'rails_helper'

# Tolzar Results → Reply-time target (round 4, G2): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; per inbox
# first replies within vs over the target; the brain's SLA when on (working hours if it says so), else 15 minutes.
RSpec.describe 'Tolzar reply-time target', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'Main desk') }
  let!(:quiet) { create(:inbox, account: account, name: 'Quiet desk') }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/reply_target" }

  def first_reply(seconds, business: nil, at: Time.current)
    ReportingEvent.create!(account_id: account.id, name: 'first_response', inbox_id: inbox.id, value: seconds,
                           value_in_business_hours: business, created_at: at)
  end

  def brain_sla(config)
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 200, 'config' => config })
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'uses the default 15 minutes when the SLA is off or the brain is down' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 502, 'ok' => false })
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      first_reply(300)
      first_reply(900)
      first_reply(901)
      first_reply(60, at: 40.days.ago)

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['target']).to eq('minutes' => 15, 'source' => 'default', 'working_hours' => false)
      expect(body['inboxes'].first).to include('name' => 'Main desk', 'within' => 2, 'late' => 1)
      expect(body['inboxes'].last).to include('name' => 'Quiet desk', 'within' => 0, 'late' => 0)
    end
  end

  it "follows the brain's SLA, in working hours when it says so" do
    brain_sla({ 'enabled' => true, 'first_reply_minutes' => 30, 'working_hours_only' => true })
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      first_reply(7200, business: 600)
      first_reply(1700)
      first_reply(7200, business: 3600)

      get url, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['target']).to eq('minutes' => 30, 'source' => 'sla', 'working_hours' => true)
      expect(body['inboxes'].first).to include('within' => 2, 'late' => 1)
    end
  end
end
