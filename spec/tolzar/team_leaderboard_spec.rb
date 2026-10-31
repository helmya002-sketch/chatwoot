require 'rails_helper'

# Tolzar Results → Team (round 4, c96): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; everyone listed,
# replies exclude private notes and older messages, first reply is the median, rating is per assigned person.
RSpec.describe 'Tolzar team leaderboard', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Amal') }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Omar') }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/team_leaderboard" }

  def reply(user, **attrs)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, sender: user,
                     message_type: :outgoing, **attrs)
  end

  def event(name, user, value)
    ReportingEvent.create!(account_id: account.id, name: name, user_id: user.id, value: value,
                           conversation_id: conversation.id, inbox_id: conversation.inbox_id)
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'lists each person with replies, median first reply, resolved and rating' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      2.times { reply(agent) }
      reply(agent, private: true)
      reply(agent, created_at: 40.days.ago)
      # On Amal, who sends no replies, so no first_response event of the app's own adds to these.
      [60, 120, 600].each { |v| event('first_response', admin, v) }
      event('conversation_resolved', agent, 1)

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, headers: admin.create_new_auth_token
      people = response.parsed_body['people']
      expect(people.pluck('name')).to eq(%w[Omar Amal])
      expect(people.first).to include('replies' => 2, 'resolved' => 1)
      expect(people.last).to include('replies' => 0, 'first_reply' => 120, 'resolved' => 0, 'csat' => nil)
    end
  end
end
