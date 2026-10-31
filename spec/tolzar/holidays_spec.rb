require 'rails_helper'

# Tolzar holiday calendar (round 4, c103): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; administrators save the list
# (cleaned: valid unique dates, sorted); on a listed day an inbox with working hours is out of office in its own
# time zone; off, the list changes nothing.
RSpec.describe 'Tolzar holidays', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: true, timezone: 'Asia/Dubai') }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/holidays" }

  before do
    inbox.working_hours.update_all(open_all_day: true, closed_all_day: false)
  end

  it 'is 404 while the switch is off, and a listed day changes nothing' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)

    account.update!(settings: { 'tolzar_holidays' => [{ 'date' => Time.current.in_time_zone('Asia/Dubai').to_date.iso8601 }] })
    expect(inbox.reload.out_of_office?).to be(false)
  end

  it 'saves a clean list for administrators and closes inboxes on those days' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      today = Time.current.in_time_zone('Asia/Dubai').to_date
      rows = [{ date: (today + 3).iso8601, name: 'Later' }, { date: today.iso8601, name: ' Today ' },
              { date: today.iso8601, name: 'Twice' }, { date: 'not a date', name: 'x' }]

      post url, params: { holidays: rows }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post url, params: { holidays: rows }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['holidays']).to eq([{ 'date' => today.iso8601, 'name' => 'Today' },
                                                      { 'date' => (today + 3).iso8601, 'name' => 'Later' }])
      expect(inbox.reload.out_of_office?).to be(true)

      get url, headers: agent.create_new_auth_token
      expect(response.parsed_body['holidays'].size).to eq(2)
    end
  end
end
