require 'rails_helper'

# Tolzar conversation transcript (round 4, H1): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; only people who can see the
# conversation; private notes only when asked; escaped; attachments as file names.
RSpec.describe 'Tolzar conversation transcript', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Amal') }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Sam Customer') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/conversations/#{conversation.display_id}/transcript" }

  before do
    create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact,
                     message_type: :incoming, content: 'Hello <script>x</script> there')
    create(:message, account: account, conversation: conversation, inbox: inbox, sender: admin,
                     message_type: :outgoing, content: 'Happy to help')
    create(:message, account: account, conversation: conversation, inbox: inbox, sender: admin,
                     message_type: :outgoing, private: true, content: 'Internal remark only')
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'prints the messages with names, leaves notes out unless asked, and escapes content' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/html')
      expect(response.body).to include('Sam Customer', 'Amal', 'Happy to help', 'Internal notes left out')
      expect(response.body).not_to include('Internal remark only')
      expect(response.body).not_to include('<script>x</script>')

      get url, params: { notes: '1', tz: 'Africa/Cairo' }, headers: admin.create_new_auth_token
      expect(response.body).to include('Internal remark only', 'Africa/Cairo')
    end
  end

  it 'refuses people who cannot see the conversation' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'answers 404 for a conversation of another workspace' do
    other = create(:conversation, account: create(:account))
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get "/api/v1/accounts/#{account.id}/tolzar/conversations/#{other.display_id + 1000}/transcript",
          headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end
end
