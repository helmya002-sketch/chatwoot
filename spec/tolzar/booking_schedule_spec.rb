require 'rails_helper'

# Tolzar bookings schedule (round 4, c102): TOLZAR_BOOKINGS_ACCOUNTS workspaces; per day and resource for the next
# 14 days, a resource on two bookings the same day is a clash; cancelled bookings and lines with no resource are out.
RSpec.describe 'Tolzar booking schedule', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/booking_schedule" }
  let(:day) { Date.current + 2 }

  def booking(status, resource, date: day, until_date: nil)
    line = { type: 'rental', description: 'Boat day', unit_price: '50', date: date.iso8601, resource: resource }
    line[:until] = until_date.iso8601 if until_date
    b = Tolzar::Booking.create!(account: account, currency: 'USD', data: { lines: [line] })
    b.update_columns(status: status)
    b
  end

  it 'is 404 while the switch is off' do
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'groups by day and resource and flags clashes' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      booking('confirmed', 'Boat 2', until_date: day + 1)
      booking('draft', 'boat 2 ')
      booking('cancelled', 'Boat 2')
      booking('confirmed', nil)

      get url, headers: agent.create_new_auth_token
      body = response.parsed_body
      on = ->(date) { body['days'].find { |d| d['date'] == date.iso8601 }['resources'] }
      expect(on.call(day).size).to eq(1)
      expect(on.call(day).first).to include('resource' => 'Boat 2', 'clash' => true)
      expect(on.call(day).first['items'].size).to eq(2)
      expect(on.call(day + 1).first).to include('clash' => false)
      expect(body['clashes']).to eq(1)
    end
  end
end
