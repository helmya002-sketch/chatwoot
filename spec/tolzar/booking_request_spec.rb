require 'rails_helper'

# Tolzar public booking request (round 4, D1): TOLZAR_BOOKINGS_ACCOUNTS + TOLZAR_BOOKING_REQUESTS_ACCOUNTS
# workspaces; administrators copy/reset the link; a request makes a contact and a draft booking, never a send;
# the honeypot saves nothing; a reset ends the old link; 404 otherwise.
RSpec.describe 'Tolzar booking request', type: :request do
  let(:account) { create(:account, name: 'Harbour Studio') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:api) { "/api/v1/accounts/#{account.id}/tolzar/booking_request_link" }
  let(:switches) { { TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s, TOLZAR_BOOKING_REQUESTS_ACCOUNTS: account.id.to_s } }
  let(:form) do
    { date: (Date.current + 5).iso8601, people: '3', name: 'Sam Example', reach: 'sam@tolzar.com', note: 'Morning if possible' }
  end

  def link_path
    get api, headers: admin.create_new_auth_token
    URI.parse(response.parsed_body['url']).path
  end

  it 'is 404 while the switch is off, and for a bad token' do
    get api, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    path = "/tz/book/#{account.id}/#{Tolzar::BookingRequest.token(account)}"
    get path
    expect(response).to have_http_status(:not_found)

    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      get path
      expect(response).to have_http_status(:not_found)
    end

    with_modified_env(**switches) do
      get "/tz/book/#{account.id}/#{'a' * 64}"
      expect(response).to have_http_status(:not_found)
      post "/tz/book/#{account.id}/#{'a' * 64}", params: form
      expect(response).to have_http_status(:not_found)
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Harbour Studio')
    end
  end

  it 'lets administrators only see the link' do
    with_modified_env(**switches) do
      get api, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      get api, headers: admin.create_new_auth_token
      expect(response.parsed_body['url']).to include("/tz/book/#{account.id}/")
    end
  end

  it 'creates a contact and a draft booking, and a private note where an API inbox exists' do
    inbox = create(:channel_api, account: account).inbox
    with_modified_env(**switches) do
      expect { post link_path, params: form }.to change(Tolzar::Booking, :count).by(1).and change(Contact, :count).by(1)
      expect(response).to have_http_status(:ok)

      booking = Tolzar::Booking.last
      expect(booking.status).to eq('draft')
      expect(booking.account_id).to eq(account.id)
      expect(booking.contact.email).to eq('sam@tolzar.com')
      expect(booking.data['lines'].first).to include('description' => 'Booking request', 'qty' => 3)
      expect(booking.starts_on).to eq(Date.current + 5)

      note = booking.conversation.messages.last
      expect(booking.conversation.inbox_id).to eq(inbox.id)
      expect(note.private).to be(true)
      expect(note.content).to include('Sam Example')

      expect { post link_path, params: form }.not_to change(Contact, :count)
    end
  end

  it 'keeps just the draft when the workspace has no API inbox' do
    with_modified_env(**switches) do
      expect { post link_path, params: form }.to change(Tolzar::Booking, :count).by(1)
      expect(Tolzar::Booking.last.conversation).to be_nil
      expect(Conversation.where(account_id: account.id).count).to eq(0)
    end
  end

  it 'shows the form again for a bad request and saves nothing' do
    with_modified_env(**switches) do
      expect { post link_path, params: form.merge(people: '0', note: 'x' * 501) }.not_to change(Tolzar::Booking, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'pretends success and saves nothing when the honeypot is filled' do
    with_modified_env(**switches) do
      path = link_path
      expect { post path, params: form.merge(website: 'http://spam.example') }
        .not_to change(Tolzar::Booking, :count)
      expect(response).to have_http_status(:ok)
      expect(Contact.where(account_id: account.id, email: 'sam@tolzar.com')).not_to exist
    end
  end

  it 'ends the old link on a reset' do
    with_modified_env(**switches) do
      old = link_path
      post "#{api}/reset", headers: admin.create_new_auth_token
      fresh = URI.parse(response.parsed_body['url']).path
      expect(fresh).not_to eq(old)
      get old
      expect(response).to have_http_status(:not_found)
      get fresh
      expect(response).to have_http_status(:ok)
    end
  end
end
