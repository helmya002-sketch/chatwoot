require 'rails_helper'

# Tolzar Results → Bookings card and the bookings export (c58): per currency, never summed across currencies;
# administrators only; 404 when both switches are off; CSV cells cannot run as formulas.
RSpec.describe 'Tolzar booking results', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: '=HYPERLINK("http://x.test")') }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar" }

  def booking(currency, price, status)
    b = Tolzar::Booking.create!(account: account, contact: contact, currency: currency,
                                data: { lines: [{ type: 'service', description: 'Boat day', unit_price: price, date: Date.current.iso8601 }],
                                        payments: [{ amount: '10' }] })
    b.update_columns(status: status)
    b
  end

  it 'is 404 with both switches off and admin only' do
    get "#{base}/booking_results", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      get "#{base}/booking_results", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'reports bookings per status and money per currency' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      booking('EUR', '100', 'confirmed')
      booking('EUR', '50', 'completed')
      booking('USD', '30', 'confirmed')
      booking('USD', '999', 'cancelled')
      get "#{base}/booking_results", params: { days: 7 }, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['days']).to eq(7)
      expect(body['documents']).to be_nil
      expect(body['bookings']['by_status']).to include('confirmed' => 2, 'completed' => 1, 'cancelled' => 1)
      expect(body['bookings']['money']).to eq([
                                                { 'currency' => 'EUR', 'total_cents' => 15_000, 'paid_cents' => 2000, 'due_cents' => 13_000 },
                                                { 'currency' => 'USD', 'total_cents' => 3000, 'paid_cents' => 1000, 'due_cents' => 2000 }
                                              ])
      get "#{base}/bookings/agenda", headers: admin.create_new_auth_token
      expect(response.parsed_body['balances_due_by_currency']).to contain_exactly(
        { 'currency' => 'EUR', 'cents' => 13_000 }, { 'currency' => 'USD', 'cents' => 2000 }
      )
    end
  end

  it 'counts issued documents per type and currency' do
    with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) do
      doc = Tolzar::Document.create!(account: account, contact: contact, doc_type: 'voucher', currency: 'EUR',
                                     spec: { lines: [{ type: 'service', description: 'Boat day', unit_price: '60' }] })
      doc.issue!(by: admin)
      get "#{base}/booking_results", headers: admin.create_new_auth_token
      docs = response.parsed_body['documents']
      expect(docs).to include('issued' => 1, 'cancelled' => 0, 'by_type' => { 'voucher' => 1 })
      expect(docs['money'].first).to include('currency' => 'EUR', 'total_cents' => 6000)
      expect(response.parsed_body['bookings']).to be_nil
    end
  end

  it 'exports bookings as CSV with formula cells made text' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      booking('EUR', '100', 'confirmed')
      get "#{base}/bookings/export", headers: admin.create_new_auth_token
      expect(response.media_type).to eq('text/csv')
      rows = CSV.parse(response.body)
      expect(rows.first).to include('status', 'currency', 'due')
      expect(rows.second[4]).to start_with("'=HYPERLINK")
      expect(rows.second).to include('confirmed', 'EUR', '100.00', '10.00', '90.00')
    end
  end

  it 'makes formula cells text' do
    expect(Tolzar::CsvCell.safe('=1+1')).to eq("'=1+1")
    expect(Tolzar::CsvCell.safe('-2')).to eq("'-2")
    expect(Tolzar::CsvCell.safe('Mona')).to eq('Mona')
    expect(Tolzar::CsvCell.safe(nil)).to eq(nil)
  end
end
