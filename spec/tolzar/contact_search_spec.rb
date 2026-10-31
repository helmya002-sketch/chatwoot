require 'rails_helper'

# Tolzar search within a contact (round 4, E5): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; q of 2-100 characters; hits
# only from conversations the viewer may see; '%' and '_' in q are matched literally.
RSpec.describe 'Tolzar contact search', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/contacts/#{contact.id}/search" }
  let(:seen) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:hidden) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

  def add_message(conversation, content, **attrs)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, content: content, **attrs)
  end

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'is 404 while the switch is off' do
    get url, params: { q: 'invoice' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'is 422 for a one-character query' do
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, params: { q: 'a' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'finds a match, private notes included, with a short plain-text snippet' do
    add_message(seen, "#{'x' * 300} the Invoice is ready #{'y' * 300}", message_type: :incoming)
    note = add_message(seen, 'Sent the invoice by hand', message_type: :outgoing, private: true)
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, params: { q: 'invoice' }, headers: admin.create_new_auth_token
      results = response.parsed_body['results']
      expect(results.size).to eq(2)
      expect(results.first).to include('conversation_id' => seen.display_id, 'message_id' => note.id)
      expect(results.last['snippet'].length).to be <= 160
      expect(results.last['snippet']).to include('Invoice is ready')
    end
  end

  it 'never returns a conversation in an inbox the agent cannot see' do
    add_message(seen, 'invoice one', message_type: :incoming)
    add_message(hidden, 'invoice two', message_type: :incoming)
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, params: { q: 'invoice' }, headers: agent.create_new_auth_token
      expect(response.parsed_body['results'].pluck('conversation_id')).to eq([seen.display_id])
    end
  end

  it "matches '%' literally" do
    add_message(seen, 'we are 100% sure', message_type: :incoming)
    add_message(seen, 'we are 1000 sure', message_type: :incoming)
    with_modified_env(TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s) do
      get url, params: { q: '0% s' }, headers: admin.create_new_auth_token
      expect(response.parsed_body['results'].pluck('snippet')).to eq(['we are 100% sure'])
    end
  end
end
