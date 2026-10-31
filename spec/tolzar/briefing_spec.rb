require 'rails_helper'

# Tolzar briefing bar: GET tolzar/briefing counts hot leads (lead score >= 70, open) among the conversations the
# member may open; agents see only their inboxes; a score that is not a number never breaks the query.
RSpec.describe 'Tolzar briefing', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:mine) { create(:inbox, account: account) }
  let(:other) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/briefing" }

  before { create(:inbox_member, user: agent, inbox: mine) }

  def lead(inbox, score, status: :open, name: 'Lead')
    contact = create(:contact, account: account, name: name,
                               custom_attributes: { tolzar_lead_score: score, tolzar_lead_hint: 'asked for dates' })
    create(:conversation, account: account, inbox: inbox, contact: contact, status: status)
  end

  it 'lists hot open leads by score, for what each member may open' do
    top = lead(other, 92, name: 'Mona')
    lead(mine, 75, name: 'Omar')
    lead(mine, 60)
    lead(mine, 99, status: :resolved)
    lead(mine, 'n/a')
    lead(mine, '')

    get url, headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['hot_count']).to eq(2)
    expect(body['hot'].first).to include('id' => top.display_id, 'name' => 'Mona', 'score' => 92, 'hint' => 'asked for dates')

    get url, headers: agent.create_new_auth_token
    body = response.parsed_body
    expect(body['hot_count']).to eq(1)
    expect(body['hot'].pluck('name')).to eq(['Omar'])
  end

  it 'never shows another workspace' do
    elsewhere = create(:account)
    create(:conversation, account: elsewhere, inbox: create(:inbox, account: elsewhere),
                          contact: create(:contact, account: elsewhere, custom_attributes: { tolzar_lead_score: 95 }))
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('hot_count' => 0, 'hot' => [])
  end

  it 'needs a signed-in member' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'the top bar (c62)' do
    before { allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 503 }) }

    it 'sends no counts and no AI state while the switch is off' do
      get url, headers: admin.create_new_auth_token
      expect(response.parsed_body.keys).not_to include('now', 'ai')
    end

    it 'counts mine, waiting, unassigned and follow-ups due today, for what each member may open' do
      with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s) do
        create(:conversation, account: account, inbox: mine, assignee: agent, status: :open)
        # Replied and not waiting again (a new conversation always starts as waiting): attended.
        create(:conversation, account: account, inbox: mine, status: :open)
          .update_columns(first_reply_created_at: 1.hour.ago, waiting_since: nil)
        create(:conversation, account: account, inbox: other, status: :open)
        create(:conversation, account: account, inbox: mine, status: :snoozed, snoozed_until: Time.current.utc.beginning_of_day + 1.minute)
        create(:conversation, account: account, inbox: mine, status: :snoozed, snoozed_until: 3.days.from_now)

        get url, params: { tz: 'UTC' }, headers: agent.create_new_auth_token
        now = response.parsed_body['now']
        expect(now).to include('mine' => 1, 'unassigned' => 1, 'due_today' => 1)
        expect(now['waiting']).to eq(1) # the agent's own unattended open one; the other inbox is not theirs
        expect(now).not_to have_key('bookings_today')

        get url, headers: admin.create_new_auth_token
        expect(response.parsed_body['now']).to include('unassigned' => 2)
      end
    end

    it 'shows the AI as the brain reports it, and unknown when it does not answer' do
      with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s) do
        get url, headers: admin.create_new_auth_token
        expect(response.parsed_body['ai']).to eq('unknown')

        allow(Tolzar::BrainClient).to receive(:get).with('/workspace/settings', account_id: account.id)
                                                   .and_return({ 'status' => 200, 'kill_switch_on' => false,
                                                                 'inbox_modes' => { mine.id.to_s => { 'mode' => 'shadow' } } })
        get url, headers: admin.create_new_auth_token
        expect(response.parsed_body['ai']).to eq('shadow')

        allow(Tolzar::BrainClient).to receive(:get).with('/workspace/settings', account_id: account.id)
                                                   .and_return({ 'status' => 200, 'kill_switch_on' => true, 'inbox_modes' => {} })
        get url, headers: admin.create_new_auth_token
        expect(response.parsed_body['ai']).to eq('off')
      end
    end

    it "gives My day: the longest waiting, follow-ups due, and today's replies, resolved and median first reply" do
      with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s) do
        old = create(:conversation, account: account, inbox: mine, status: :open)
        old.update_columns(waiting_since: 3.hours.ago)
        newer = create(:conversation, account: account, inbox: mine, status: :open)
        newer.update_columns(waiting_since: 10.minutes.ago)
        create(:message, account: account, conversation: newer, inbox: mine, sender: agent, message_type: :outgoing)
        create(:message, account: account, conversation: newer, inbox: mine, sender: agent, message_type: :outgoing, private: true)
        [60, 120, 300].each { |v| ReportingEvent.create!(account_id: account.id, user_id: agent.id, name: 'first_response', value: v) }
        ReportingEvent.create!(account_id: account.id, user_id: agent.id, name: 'conversation_resolved', value: 0)

        get url, params: { tz: 'UTC' }, headers: agent.create_new_auth_token
        day = response.parsed_body['day']
        expect(day['waiting'].first['id']).to eq(old.display_id)
        expect(day['today']).to eq('replied' => 1, 'resolved' => 1, 'median_first_reply' => 120)
      end
    end

    it 'counts bookings today when bookings are on' do
      with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s, TOLZAR_BOOKINGS_ACCOUNTS: account.id.to_s) do
        today = Time.current.utc.to_date.iso8601
        Tolzar::Booking.create!(account: account, currency: 'EUR',
                                data: { lines: [{ type: 'service', description: 'Boat day', unit_price: '60', date: today }] })
        get url, params: { tz: 'UTC' }, headers: admin.create_new_auth_token
        expect(response.parsed_body.dig('now', 'bookings_today')).to eq(1)
      end
    end
  end
end
