require 'rails_helper'

# Tolzar booking documents, c57: the workspace template (owner), industry-pack line types and default terms, and
# privacy: DSAR export, contact erase and the retention period reach documents and bookings, while issued numbers
# and totals stay in the register.
RSpec.describe 'Tolzar document template and privacy', type: :request do
  let(:account) { create(:account, name: 'Nile Boats') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Mona Adel', email: 'mona@example.com') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:docs) { "/api/v1/accounts/#{account.id}/tolzar/documents" }
  let(:logo) { "data:image/png;base64,#{Base64.strict_encode64('png-bytes')}" }

  around { |example| with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run } }

  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:post_to_brain).and_return({ 'ok' => true, 'deleted' => {} })
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 200 })
  end

  def spec_for(name)
    { guests: [{ name: name }], notes: "#{name} likes the front seats",
      lines: [{ type: 'service', description: "Boat day for #{name}", unit_price: '60' }],
      payments: [{ amount: '20', reference: 'card 4242' }] }
  end

  def issued_doc
    doc = Tolzar::Document.create!(account: account, contact: contact, conversation: conversation, doc_type: 'voucher',
                                   currency: 'EUR', spec: spec_for('Mona Adel'))
    doc.issue!(by: owner)
    doc
  end

  it 'saves the template for the owner only, refuses a logo URL, and returns the packs' do
    post "#{docs}_settings", params: { branding: { colour: '#0E7490', logo: logo, address: 'Marina 3, Hurghada',
                                                   terms: { voucher: 'Bring a towel.' } } },
                             headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{docs}_settings", params: { branding: { logo: 'https://example.com/logo.png' } }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "#{docs}_settings", params: { branding: { colour: '#0E7490', logo: logo, address: 'Marina 3, Hurghada',
                                                   terms: { voucher: 'Bring a towel.' } } },
                             headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['branding']).to include('colour' => '#0E7490', 'address' => 'Marina 3, Hurghada')
    expect(body['line_types']['room_night']).to include('nights')
    expect(body['default_terms']['payment_summary']).to include('not a tax invoice')
    expect(body['prefixes']['voucher']).to eq('VCH')

    rendered = Tolzar::DocumentBranding.for_render(account.reload, 'voucher')
    expect(rendered).to include(colour: '#0E7490', terms: 'Bring a towel.', logo: logo)
    expect(Tolzar::DocumentBranding.for_render(account, 'quote')[:terms]).to eq(Tolzar::DocumentPacks.default_terms('quote'))
  end

  it 'prints with the template' do
    account.update!(settings: { Tolzar::DocumentBranding::KEY => { 'colour' => '#0E7490', 'address' => 'Marina 3' } })
    doc = issued_doc
    get "#{docs}/#{doc.id}/print", headers: agent.create_new_auth_token
    expect(response.body).to include('#0E7490', 'Marina 3', 'Good to know', 'Show this voucher')
  end

  it 'exports and erases the person in documents and bookings, keeping the issued number and totals' do
    doc = issued_doc
    draft = Tolzar::Document.create!(account: account, contact: contact, doc_type: 'quote', currency: 'EUR', spec: spec_for('Mona Adel'))
    booking = Tolzar::Booking.create!(account: account, contact: contact, conversation: conversation, currency: 'EUR',
                                      data: spec_for('Mona Adel'))

    get "/api/v1/accounts/#{account.id}/tolzar/data/contact_records", params: { contact_id: contact.id },
                                                                      headers: owner.create_new_auth_token
    expect(response.parsed_body['documents'].size).to eq(2)
    expect(response.parsed_body['bookings'].size).to eq(1)

    post "/api/v1/accounts/#{account.id}/tolzar/data/contact_erase", params: { contact_id: contact.id, confirm: 'Mona Adel' },
                                                                     headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Tolzar::Document.exists?(draft.id)).to be(false)
    doc.reload
    expect(doc).to have_attributes(number: doc.number, total_cents: 6000, contact_id: nil, conversation_id: nil)
    expect(doc.spec.to_json).not_to include('Mona')
    expect(doc.spec.to_json).not_to include('4242')
    expect(doc.history.last['action']).to eq('erased')
    expect(booking.reload.data.to_json).not_to include('Mona')
    expect(booking.contact_id).to be_nil
  end

  it 'anonymises documents of conversations the retention period deletes' do
    doc = issued_doc
    account.update!(settings: { Tolzar::ConversationRetention::KEY => 365 })
    conversation.update_columns(last_activity_at: 2.years.ago)
    expect(Tolzar::ConversationRetention.new(account).purge).to eq(1)
    expect(doc.reload.spec.to_json).not_to include('Mona')
    expect(doc.history.last['action']).to eq('retention')
  end

  it 'keeps another workspace untouched' do
    other = create(:account)
    theirs = Tolzar::Document.create!(account: other, contact: create(:contact, account: other), doc_type: 'quote',
                                      currency: 'EUR', spec: spec_for('Mona Adel'))
    theirs.update_columns(contact_id: contact.id) # same contact id, other workspace: scoping is by account too
    Tolzar::DocumentPrivacy.new(account).erase!(contact)
    expect(theirs.reload.spec.to_json).to include('Mona')
  end
end
