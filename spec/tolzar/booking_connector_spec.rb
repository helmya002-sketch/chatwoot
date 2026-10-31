require 'rails_helper'

# Tolzar booking-system connector (DWT Bookings first): owner-only connect with a write-only encrypted token, a
# test call, a guest's bookings read-only, and a DRAFT booking from a Tolzar document (catalog lines only, no
# prices); only for TOLZAR_BOOKING_CONNECTOR workspaces.
RSpec.describe 'Tolzar booking connector', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar/booking_connector" }
  let(:fake) { instance_double(Tolzar::BookingConnectors::Dwt) }

  around do |example|
    with_modified_env(TOLZAR_BOOKING_CONNECTOR: account.id.to_s, TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run }
  end

  # The token is encrypted at rest (Active Record encryption). Without the ACTIVE_RECORD_ENCRYPTION_* keys (the
  # gate's first pass) the examples that store one skip; the gate's keyed pass runs them (as encrypted_credentials).
  def needs_keys!
    skip 'ACTIVE_RECORD_ENCRYPTION_* keys are not set' unless Chatwoot.encryption_configured?
  end

  def connect(user: owner, **body)
    post base, params: { adapter: 'dwt', base_url: 'https://bookings.example.com/admin/bookings/api.php', token: 'dwtbk_secret1' }.merge(body),
               headers: user.create_new_auth_token, as: :json
  end

  it 'is 404 for a workspace not switched on' do
    with_modified_env(TOLZAR_BOOKING_CONNECTOR: '') do
      get base, headers: owner.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'lets only the owner connect, keeps the token encrypted and never returns it' do
    needs_keys!
    connect(user: agent)
    expect(response).to have_http_status(:forbidden)
    connect(base_url: 'http://bookings.example.com/api.php')
    expect(response).to have_http_status(:unprocessable_entity)
    connect
    expect(response.parsed_body.dig('connector', 'token')).to eq('set')
    expect(response.body).not_to include('dwtbk_secret1')
    raw = ActiveRecord::Base.connection.select_value('SELECT token FROM tolzar_booking_connectors LIMIT 1')
    expect(raw).not_to include('dwtbk_secret1')
    connect(token: '')
    expect(Tolzar::BookingConnector.sole.token).to eq('dwtbk_secret1')
  end

  it 'tests the connection with a read call and keeps only the outcome' do
    needs_keys!
    connect
    allow_any_instance_of(Tolzar::BookingConnector).to receive(:client).and_return(fake) # rubocop:disable RSpec/AnyInstance
    allow(fake).to receive(:catalog).and_return([{ 'slug' => 'open-water' }, { 'slug' => 'advanced' }])
    post "#{base}/test", headers: owner.create_new_auth_token
    expect(response.parsed_body).to include('ok' => true, 'catalog' => 2)
    expect(Tolzar::BookingConnector.sole.last_test_ok).to be(true)
  end

  it "reads a guest's bookings and sends a document as a draft booking without prices" do
    needs_keys!
    connect
    contact = create(:contact, account: account, phone_number: '+41791234567', name: 'Sara')
    conversation = create(:conversation, account: account, contact: contact)
    allow_any_instance_of(Tolzar::BookingConnector).to receive(:client).and_return(fake) # rubocop:disable RSpec/AnyInstance
    allow(fake).to receive(:bookings).with(phone: '+41791234567').and_return([{ 'voucher_no' => 'DWT-26-0002', 'balance' => 50 }])
    get "#{base}/bookings", params: { contact_id: contact.id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['bookings'].first['voucher_no']).to eq('DWT-26-0002')

    document = Tolzar::Document.create!(
      account: account, conversation: conversation, contact: contact, doc_type: 'quote', currency: 'EUR',
      spec: { 'guests' => [{ 'name' => 'Sara' }, { 'name' => 'Omar' }],
              'lines' => [{ 'type' => 'course', 'description' => 'Intro to tech', 'catalog_ref' => 'intro-to-technical-diving',
                            'date' => '2026-11-16', 'unit_price' => '300' },
                          { 'type' => 'extra', 'description' => 'Hotel pick-up', 'unit_price' => '20' }] }
    )
    expect(fake).to receive(:create_draft) do |body|
      expect(body[:lines]).to eq([{ course: 'intro-to-technical-diving', day: '2026-11-16', guests: 'all' }])
      expect(body[:guests].first).to include(name: 'Sara', phone: '+41791234567', tolzar_contact_id: contact.id.to_s)
      expect(body[:tolzar_conversation_id]).to eq(conversation.display_id.to_s)
      expect(body.to_json).not_to include('300')
      { 'voucher_no' => 'DWT-26-0009', 'status' => 'draft' }
    end
    post "#{base}/draft", params: { document_id: document.id }, headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('ok' => true, 'skipped' => ['Hotel pick-up'])
    expect(document.reload.history.last['action']).to eq('sent_to_booking_system')
  end

  it 'builds DWT URLs on the one endpoint with ?r=' do
    client = Tolzar::BookingConnectors::Dwt.new(base_url: 'https://b.example.com/api.php', token: 't')
    expect(client.send(:url, 'bookings', phone: '+41 79')).to eq('https://b.example.com/api.php?r=bookings&phone=%2B41+79')
  end
end
