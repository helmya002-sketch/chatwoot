require 'rails_helper'

# Tolzar booking documents, step 1: drafts and versions, the checks (totals, mismatch stop, placeholders block
# issuing, discounts only as negative lines, no ID numbers), gapless numbers per type and year, void keeps the
# number, the register and its CSV; only for TOLZAR_BOOKING_DOCS_ACCOUNTS.
RSpec.describe 'Tolzar booking documents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:spec) do
    { title: 'Your booking', guests: [{ name: 'Sara' }, { name: 'Omar' }],
      lines: [{ type: 'course', description: 'Open Water course', qty: 2, unit_price: '350.00', date: '2026-12-01' },
              { type: 'rental', description: 'Full gear, 3 days', qty: 2, unit_price: '45' },
              { type: 'discount', description: 'Group discount', qty: 1, unit_price: '-40' }],
      payments: [{ amount: '200', date: '2026-11-01', method: 'card' }], stated_total: '750', terms: 'Bring your passport.' }
  end
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar/documents" }

  around { |example| with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run } }

  def create_draft(body = {}, user: agent)
    post base, params: { doc_type: 'voucher', conversation_id: conversation.display_id, currency: 'USD', spec: spec }.merge(body),
               headers: user.create_new_auth_token, as: :json
    response.parsed_body['document']
  end

  it 'answers 404 for a workspace that is not switched on' do
    with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: '') do
      get base, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'computes totals and the payment state, and issues gapless numbers per type' do
    doc = create_draft
    expect(response).to have_http_status(:created)
    expect(doc).to include('status' => 'draft', 'number' => nil, 'total_cents' => 75_000, 'paid_cents' => 20_000,
                           'payment_state' => 'deposit')
    expect(doc['conversation_id']).to eq(conversation.display_id)

    post "#{base}/#{doc['id']}/issue", headers: agent.create_new_auth_token
    year = Time.current.year % 100
    expect(response.parsed_body.dig('document', 'number')).to eq(format('VCH-%02d-0001', year))
    second = create_draft
    post "#{base}/#{second['id']}/issue", headers: agent.create_new_auth_token
    expect(response.parsed_body.dig('document', 'number')).to eq(format('VCH-%02d-0002', year))
    quote = create_draft(doc_type: 'quote')
    post "#{base}/#{quote['id']}/issue", headers: agent.create_new_auth_token
    expect(response.parsed_body.dig('document', 'number')).to eq(format('QTE-%02d-0001', year))
  end

  it 'stops a stated total that disagrees and a placeholder at issue, and keeps drafts editable' do
    doc = create_draft(spec: spec.merge(stated_total: '999'))
    post "#{base}/#{doc['id']}/issue", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('does not match')

    patch "#{base}/#{doc['id']}", params: { spec: spec.merge(lines: spec[:lines] + [{ type: 'extra', description: 'Transfer', unit_price: 'TBC' }]) },
                                  headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('document', 'version')).to eq(2)
    expect(response.parsed_body.dig('document', 'placeholders')).to eq(['lines.3.unit_price'])
    post "#{base}/#{doc['id']}/issue", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('placeholders')
  end

  it 'never stores an ID or passport number, and only a discount line is negative' do
    create_draft(spec: spec.merge(guests: [{ name: 'Sara', passport_number: 'A1234567' }]))
    expect(response).to have_http_status(:unprocessable_entity)
    create_draft(spec: spec.merge(notes: 'Passport no. A12345678'))
    expect(response).to have_http_status(:unprocessable_entity)
    doc = create_draft(spec: spec.merge(lines: [{ type: 'service', description: 'Refund', unit_price: '-10' }]))
    post "#{base}/#{doc['id']}/issue", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('only a discount line can be negative')
  end

  it 'voids an issued document (administrators), keeps its number, and lists the register and CSV' do
    doc = create_draft
    post "#{base}/#{doc['id']}/issue", headers: agent.create_new_auth_token
    number = response.parsed_body.dig('document', 'number')
    post "#{base}/#{doc['id']}/void", params: { reason: 'Guest cancelled' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    post "#{base}/#{doc['id']}/void", params: { reason: 'Guest cancelled' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['document']).to include('status' => 'void', 'number' => number)
    patch "#{base}/#{doc['id']}", params: { spec: spec }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    get base, params: { q: number }, headers: agent.create_new_auth_token
    expect(response.parsed_body['documents'].pluck('number')).to eq([number])
    get "#{base}/export", headers: admin.create_new_auth_token
    expect(response.body.lines.first).to start_with('number,type,status')
    expect(response.body).to include(number, 'Guest cancelled')
  end
end
