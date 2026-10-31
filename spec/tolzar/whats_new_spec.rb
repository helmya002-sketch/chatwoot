require 'rails_helper'

# Tolzar "What's new" (round 4, c90): release notes filtered per workspace: an item tied to a switch shows only where
# that switch lists the workspace; a release with nothing left is dropped; a malformed switch name never matches.
RSpec.describe 'Tolzar whats new', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:notes) do
    [{ 'release' => 'r2', 'date' => '2026-11-01',
       'items' => [{ 'title' => 'Everyone', 'text' => 'a' }, { 'title' => 'Bookings', 'text' => 'b', 'switch' => 'TOLZAR_BOOKINGS_ACCOUNTS' }] },
     { 'release' => 'r1', 'date' => '2026-10-01', 'items' => [{ 'title' => 'Hidden', 'text' => 'c', 'switch' => 'PATH' }] }]
  end

  it 'shows switched items only where the switch is on, and drops empty releases' do
    expect(Tolzar::WhatsNew.for(account.id, notes)).to eq([{ release: 'r2', date: '2026-11-01', items: [{ 'title' => 'Everyone', 'text' => 'a' }] }])
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      expect(Tolzar::WhatsNew.for(account.id, notes).first[:items].pluck('title')).to eq(%w[Everyone Bookings])
    end
  end

  it 'serves the shipped notes to any member and reads the real file' do
    get "/api/v1/accounts/#{account.id}/tolzar/whats_new", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body['releases'].flat_map { |r| r['items'].pluck('title') }
    expect(titles).to include('A clearer "reply window closed" message')
    expect(titles).not_to include('Bookings')
  end
end
