require 'rails_helper'

# Tolzar lead intake (TikTok plan row 5, any source): a lead becomes a contact on the first pipeline stage and a
# labelled conversation with the answers; per-inbox secret URL; only for TOLZAR_LEAD_INTAKE workspaces.
RSpec.describe 'Tolzar lead intake', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:token) { Tolzar::LeadIntake.token(inbox) }
  let(:lead) do
    { source: 'tiktok', lead_id: 'tt-lead-1', name: 'Omar Said', email: 'Omar@Example.com', phone: '+201001234567',
      campaign: 'Spring', ad: 'Video A', form: 'Get a quote',
      answers: [{ question: 'How many people?', answer: '4' }, { name: 'Budget', value: '500 USD' }] }
  end

  around { |example| with_modified_env(TOLZAR_LEAD_INTAKE: account.id.to_s) { example.run } }

  before { Redis::Alfred.delete("tolzar:leads:#{inbox.id}:#{Time.current.strftime('%Y%m%d%H')}") }

  def send_lead(body = lead, tok = token)
    post "/tolzar/leads/#{inbox.id}/#{tok}", params: body.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  it 'creates the contact on the first stage and a labelled conversation with the answers' do
    expect { send_lead }.to change(Conversation, :count).by(1)
    expect(response).to have_http_status(:created)
    conversation = Conversation.find(response.parsed_body['conversation_id'])
    contact = conversation.contact
    expect(contact.email).to eq('omar@example.com')
    expect(contact.phone_number).to eq('+201001234567')
    expect(contact.custom_attributes).to include('lifecycle_stage' => 'New Lead', 'lead_source' => 'tiktok',
                                                 'lead_campaign' => 'Spring', 'lead_ad' => 'Video A')
    expect(conversation.label_list).to contain_exactly('lead', 'lead-tiktok')
    expect(conversation.messages.incoming.sole.content).to include('How many people?: 4', 'Budget: 500 USD', 'Campaign: Spring')
  end

  it 'answers a lead seen again without a second conversation, and keeps an existing contact stage' do
    send_lead
    expect { send_lead }.not_to change(Conversation, :count)
    expect(response.parsed_body['duplicate']).to be(true)

    contact = Contact.find_by(email: 'omar@example.com')
    contact.update!(custom_attributes: contact.custom_attributes.merge('lifecycle_stage' => 'Customer Won'))
    send_lead(lead.merge(lead_id: 'tt-lead-2'))
    expect(contact.reload.custom_attributes['lifecycle_stage']).to eq('Customer Won')
    expect(account.contacts.where(email: 'omar@example.com').count).to eq(1)
  end

  it 'keeps a local phone number in the message, not on the contact' do
    send_lead(lead.merge(lead_id: 'tt-3', email: nil, phone: '0100 123 4567'))
    conversation = Conversation.find(response.parsed_body['conversation_id'])
    expect(conversation.contact.phone_number).to be_nil
    expect(conversation.messages.first.content).to include('Phone: 0100 123 4567')
  end

  it 'answers 404 for a wrong token or a workspace not switched on, and 422 without any contact detail' do
    send_lead(lead, 'wrong')
    expect(response).to have_http_status(:not_found)
    with_modified_env(TOLZAR_LEAD_INTAKE: '') do
      send_lead
      expect(response).to have_http_status(:not_found)
    end
    send_lead({ source: 'web', answers: { 'Q' => 'A' } })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows the lead URLs to the workspace owner only" do
    owner = create(:user, account: account, role: :administrator)
    other_admin = create(:user, account: account, role: :administrator)
    inbox
    get "/api/v1/accounts/#{account.id}/tolzar/lead_intake", headers: other_admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/accounts/#{account.id}/tolzar/lead_intake", headers: owner.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['inboxes'].first['url']).to end_with("/tolzar/leads/#{inbox.id}/#{token}")
  end
end
