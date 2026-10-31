require 'rails_helper'

# Query budgets (round 4, c85): the busiest Tolzar list endpoints make the same number of database queries for 2 rows
# as for 6, so a long list never turns into one query per row (N+1). Each example lists the endpoint twice, with more
# rows the second time, and the counts must match (a small allowance for a cache warm-up).
RSpec.describe 'Tolzar query budgets', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:api) { "/api/v1/accounts/#{account.id}/tolzar" }

  def queries_for
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:sql].to_s.start_with?('SAVEPOINT', 'RELEASE')
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    count
  end

  def expect_flat(make_row, &request)
    2.times { make_row.call }
    request.call # warm-up: caches, settings
    small = queries_for(&request)
    4.times { make_row.call }
    large = queries_for(&request)
    expect(large).to be <= small + 1, "#{large} queries for 6 rows vs #{small} for 2: one query per row?"
  end

  it 'lists documents without a query per row' do
    with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) do
      make = lambda do
        contact = create(:contact, account: account)
        conversation = create(:conversation, account: account, contact: contact)
        Tolzar::Document.create!(account: account, contact: contact, conversation: conversation,
                                 doc_type: 'quote', currency: 'EUR', spec: { lines: [{ type: 'service', description: 'Boat day', unit_price: '60' }] })
      end
      expect_flat(make) { get "#{api}/documents", headers: headers }
    end
  end

  it 'lists bookings without a query per row' do
    with_modified_env(TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
      make = lambda do
        Tolzar::Booking.create!(account: account, contact: create(:contact, account: account), currency: 'EUR',
                                data: { lines: [{ type: 'service', description: 'Boat day', unit_price: '60', date: Date.current.iso8601 }] })
      end
      expect_flat(make) { get "#{api}/bookings", headers: headers }
    end
  end

  it 'builds the briefing and My day without a query per conversation' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 })
    with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s) do
      inbox = create(:inbox, account: account)
      make = lambda do
        contact = create(:contact, account: account, custom_attributes: { tolzar_lead_score: 90 })
        create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
      end
      expect_flat(make) { get "#{api}/briefing", headers: headers }
    end
  end

  it 'lists human-agent replies without a query per row' do
    inbox = create(:inbox, account: account)
    make = lambda do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                       content_attributes: { 'tolzar_human_agent_tag' => true })
    end
    expect_flat(make) { get "#{api}/human_agent_replies", headers: headers }
  end
end
