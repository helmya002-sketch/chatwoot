require 'rails_helper'

# Tolzar bookings calendar feed (round 4, c101): TOLZAR_BOOKINGS_ACCOUNTS workspaces; a private link per person,
# confirmed/completed bookings only, no customer details; a reset or a removed person ends the link; 404 otherwise.
RSpec.describe 'Tolzar booking calendar', type: :request do
  let(:account) { create(:account, name: 'Nile Boats') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Mona Secret') }
  let(:api) { "/api/v1/accounts/#{account.id}/tolzar/booking_calendar" }

  def booking(status, starts_on)
    lines = [{ type: 'service', description: 'Boat day', unit_price: '50', date: starts_on.iso8601, until: (starts_on + 2).iso8601 }]
    b = Tolzar::Booking.create!(account: account, contact: contact, currency: 'USD', data: { lines: lines })
    b.update_columns(status: status)
    b
  end

  def feed_path(url)
    URI.parse(url).path
  end

  it 'is 404 while the switch is off' do
    get api, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "/tz/ical/#{account.id}/#{agent.id}/#{'a' * 64}.ics"
    expect(response).to have_http_status(:not_found)
  end

  it 'serves confirmed bookings without customer details, and a reset ends the old link' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      confirmed = booking('confirmed', Date.current + 3)
      booking('draft', Date.current + 4)

      get api, headers: agent.create_new_auth_token
      old = feed_path(response.parsed_body['url'])
      get old
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/calendar')
      expect(response.body).to include("UID:tolzar-booking-#{confirmed.id}@#{account.id}", 'DTEND;VALUE=DATE:')
      expect(response.body.scan('BEGIN:VEVENT').size).to eq(1)
      expect(response.body).not_to include('Mona')

      post "#{api}/reset", headers: agent.create_new_auth_token
      fresh = feed_path(response.parsed_body['url'])
      expect(fresh).not_to eq(old)
      get old
      expect(response).to have_http_status(:not_found)
      get fresh
      expect(response).to have_http_status(:ok)

      AccountUser.find_by(account: account, user: agent).destroy!
      get fresh
      expect(response).to have_http_status(:not_found)
    end
  end
end
