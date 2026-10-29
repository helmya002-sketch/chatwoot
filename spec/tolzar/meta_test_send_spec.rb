require 'rails_helper'

# The ONE App Review test message from a listen-only page inbox (Tolzar::MetaTestSend): only with the
# Owner's window open, only to a contact named like the Owner who wrote in the last 24 h, confirmed by
# typing that name, one message, audited; every other send stays refused.
RSpec.describe Tolzar::MetaTestSend do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :administrator, name: 'Ahmed Helmy') }
  let!(:meta_app) { Tolzar::MetaApp.create!(account: account, app_id: '1234567890123', app_secret: 'a' * 32) }
  let(:channel) do
    Channel::FacebookPage.create!(account: account, page_id: '1001', page_access_token: 'pt',
                                  user_access_token: 'sut', tolzar_listen_only: true)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:own) { conversation_with('Ahmed Helmy', '71000000001') }
  let(:meta) do
    stub_request(:post, 'https://graph.facebook.com/v26.0/me/messages')
      .with(headers: { 'Authorization' => 'Bearer pt' })
      .to_return(body: { message_id: 'm_1' }.to_json)
  end

  # Meta's ID matching (psid -> app-scoped id) and the app's role list.
  def meta_says_role(psid, asid, roles: [asid])
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/#{psid}/ids_for_apps})
      .to_return(body: { data: [{ id: asid, app: { id: '1234567890123' } }] }.to_json)
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/1234567890123/roles})
      .to_return(body: { data: roles.map { |u| { user: u, role: 'administrators' } } }.to_json)
  end

  def conversation_with(name, psid)
    contact = create(:contact, account: account, name: name)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: psid)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Test')
    conversation
  end

  def send_to(conversation, confirm = conversation.contact.name)
    described_class.new(account: account, user: owner, conversation_id: conversation.display_id,
                        text: 'Thanks, this is our test reply.', confirm_name: confirm).perform
  end

  it 'is refused while the window is closed' do
    meta
    expect { send_to(own) }.to raise_error(described_class::Refused, /window/)
    expect(meta).not_to have_been_requested
  end

  it 'never sends to a customer, and a refused check does not use the window' do
    meta
    described_class.open!(account, owner)
    customer = conversation_with('Jane Customer', '71000000002')
    expect { send_to(customer) }.to raise_error(described_class::Refused, /your own account/)
    expect { send_to(own, 'someone else') }.to raise_error(described_class::Refused, /confirm/)
    expect(meta).not_to have_been_requested
    expect(described_class.open_until(account)).to be_present
  end

  it 'refuses a sender Meta does not confirm as an app role holder, even with the Owner name' do
    meta
    described_class.open!(account, owner)
    meta_says_role('71000000001', '82000000002', roles: ['82000000003'])
    expect { send_to(own) }.to raise_error(described_class::Refused, /role on the app/)
    stub_request(:get, %r{/71000000001/ids_for_apps}).to_return(status: 400, body: { error: { message: 'x' } }.to_json)
    expect { send_to(own) }.to raise_error(described_class::Refused, /role on the app/)
    expect(meta).not_to have_been_requested
  end

  it 'sends exactly one message to the Owner, saves and audits it, then closes the window' do
    meta
    meta_says_role('71000000001', '82000000001')
    described_class.open!(account, owner)
    message = send_to(own)
    expect(meta).to have_been_requested.once
    expect(a_request(:post, 'https://graph.facebook.com/v26.0/me/messages')
           .with(body: hash_including('recipient' => { id: '71000000001' }.to_json))).to have_been_made.once
    expect(message).to have_attributes(message_type: 'outgoing', source_id: 'm_1')
    expect(message.content_attributes['tolzar_app_review_test']).to be(true)
    expect(described_class.open_until(account)).to be_nil
    steps = Audited::Audit.where(auditable: account, comment: 'Tolzar App Review test send').map { |a| a.audited_changes['tolzar_meta_test_send'][0] }
    expect(steps).to eq(%w[open sent close])
    expect { send_to(own) }.to raise_error(described_class::Refused, /window/)
  end
end
