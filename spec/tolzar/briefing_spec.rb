require 'rails_helper'

# Tolzar briefing bar: GET tolzar/briefing counts hot leads (lead score >= 70, open) among the conversations the
# member may open; agents see only their inboxes; a score that is not a number never breaks the query.
RSpec.describe 'Tolzar briefing', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:mine) { create(:inbox, account: account) }
  let(:other) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/briefing" }

  before { create(:inbox_member, user: agent, inbox: mine) }

  def lead(inbox, score, status: :open, name: 'Lead')
    contact = create(:contact, account: account, name: name,
                               custom_attributes: { tolzar_lead_score: score, tolzar_lead_hint: 'asked for dates' })
    create(:conversation, account: account, inbox: inbox, contact: contact, status: status)
  end

  it 'lists hot open leads by score, for what each member may open' do
    top = lead(other, 92, name: 'Mona')
    lead(mine, 75, name: 'Omar')
    lead(mine, 60)
    lead(mine, 99, status: :resolved)
    lead(mine, 'n/a')
    lead(mine, '')

    get url, headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['hot_count']).to eq(2)
    expect(body['hot'].first).to include('id' => top.display_id, 'name' => 'Mona', 'score' => 92, 'hint' => 'asked for dates')

    get url, headers: agent.create_new_auth_token
    body = response.parsed_body
    expect(body['hot_count']).to eq(1)
    expect(body['hot'].pluck('name')).to eq(['Omar'])
  end

  it 'never shows another workspace' do
    elsewhere = create(:account)
    create(:conversation, account: elsewhere, inbox: create(:inbox, account: elsewhere),
                          contact: create(:contact, account: elsewhere, custom_attributes: { tolzar_lead_score: 95 }))
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('hot_count' => 0, 'hot' => [])
  end

  it 'needs a signed-in member' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end
end
