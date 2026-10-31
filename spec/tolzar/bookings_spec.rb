require 'rails_helper'

# Tolzar native bookings: create from a conversation, totals and balance from the lines and the payments record,
# dates from the lines, status moves (placeholders block confirming), the agenda, a draft voucher from a booking.
RSpec.describe 'Tolzar bookings', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar/bookings" }
  let(:today) { Date.current }
  let(:data) do
    { guests: [{ name: 'Sara' }, { name: 'Omar' }],
      lines: [{ type: 'course', description: 'Open Water', qty: 2, unit_price: '350', date: (today + 2).iso8601, until: (today + 4).iso8601 },
              { type: 'rental', description: 'Gear', qty: 2, unit_price: '45', date: (today + 2).iso8601 }] }
  end

  around do |example|
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s, TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run }
  end

  def create_booking(body = {})
    post base, params: { conversation_id: conversation.display_id, currency: 'EUR', data: data }.merge(body),
               headers: agent.create_new_auth_token, as: :json
    response.parsed_body['booking']
  end

  it 'is 404 while the workspace is not switched on' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: '') do
      get base, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'computes totals, dates and the balance, and records payments without charging' do
    b = create_booking
    expect(b).to include('status' => 'draft', 'total_cents' => 79_000, 'starts_on' => (today + 2).iso8601,
                         'ends_on' => (today + 4).iso8601, 'payment_state' => 'due')
    expect(b['contact_id']).to eq(conversation.contact_id)
    post "#{base}/#{b['id']}/payment", params: { amount: '200', method: 'cash' }, headers: agent.create_new_auth_token
    expect(response.parsed_body['booking']).to include('paid_cents' => 20_000, 'balance_cents' => 59_000, 'payment_state' => 'deposit')
  end

  it 'moves draft -> confirmed -> completed, never back, and a placeholder blocks confirming' do
    tbc = create_booking(data: data.merge(lines: data[:lines] + [{ type: 'extra', description: 'Transfer', unit_price: 'TBC' }]))
    post "#{base}/#{tbc['id']}/status", params: { to: 'confirmed' }, headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('placeholders')

    b = create_booking
    post "#{base}/#{b['id']}/status", params: { to: 'confirmed' }, headers: agent.create_new_auth_token
    expect(response.parsed_body.dig('booking', 'status')).to eq('confirmed')
    post "#{base}/#{b['id']}/status", params: { to: 'completed' }, headers: agent.create_new_auth_token
    post "#{base}/#{b['id']}/status", params: { to: 'draft' }, headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('cannot become draft')
    patch "#{base}/#{b['id']}", params: { data: data }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to include('closed')
  end

  it 'refuses ID numbers, lists the agenda, and makes a draft voucher from a booking' do
    create_booking(data: data.merge(guests: [{ name: 'Sara', passport: 'A1234567' }]))
    expect(response).to have_http_status(:unprocessable_entity)

    b = create_booking
    get "#{base}/agenda", headers: agent.create_new_auth_token
    day = response.parsed_body['days'].find { |d| d['date'] == (today + 3).iso8601 }
    expect(day['bookings'].pluck('id')).to eq([b['id']])
    expect(response.parsed_body['balances_due']).to eq(79_000)

    post "#{base}/#{b['id']}/document", params: { doc_type: 'voucher' }, headers: agent.create_new_auth_token
    doc = response.parsed_body['document']
    expect(doc).to include('doc_type' => 'voucher', 'status' => 'draft', 'total_cents' => 79_000, 'currency' => 'EUR')
    expect(doc.dig('spec', 'booking_id')).to eq(b['id'])
  end
end
