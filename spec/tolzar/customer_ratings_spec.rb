require 'rails_helper'

# Tolzar Results → Customer ratings (round 4, G1): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; average,
# count and 1-5 distribution over the period, latest written comments with the conversation number, no contact data.
RSpec.describe 'Tolzar customer ratings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Sample Person', email: 'person@tolzar.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/customer_ratings" }

  def rating(value, text: nil, at: Time.current)
    message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox)
    create(:csat_survey_response, account: account, conversation: conversation, contact: contact, message: message,
                                  rating: value, feedback_message: text, created_at: at)
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'reports average, distribution and the latest comments without contact details' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      rating(5, text: 'Quick and clear')
      rating(4)
      rating(3, text: '')
      rating(1, text: 'Too old', at: 40.days.ago)
      create(:csat_survey_response, rating: 2)

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body).to include('ok' => true, 'days' => 30, 'count' => 3, 'average' => 4.0)
      expect(body['distribution'].pluck('count')).to eq([0, 0, 1, 1, 1])
      expect(body['comments'].size).to eq(1)
      expect(body['comments'].first).to include('rating' => 5, 'text' => 'Quick and clear',
                                                'conversation' => conversation.display_id)
      expect(response.body).not_to include('Sample Person', 'person@tolzar.com')

      get url, params: { days: 90 }, headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('days' => 90, 'count' => 4)
    end
  end
end
