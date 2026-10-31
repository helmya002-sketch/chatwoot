require 'rails_helper'

# Tolzar follow-up reminders (round 4, E4): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces; each person sets, reads and cancels
# their own reminder on a conversation they may see; the job notifies in-app when it is due and the customer has not
# written since; a customer message removes the reminders; the top bar counts them as follow-ups due today.
RSpec.describe 'Tolzar follow-up reminders', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/conversations/#{conversation.display_id}/follow_up" }
  let(:switch_on) { { TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s } }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def due_notifications(user)
    Notification.where(user: user, notification_type: 'tolzar_follow_up_due')
  end

  it 'is 404 while the switch is off' do
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    post url, params: { days: 1 }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(Tolzar::FollowUpReminder.count).to eq(0)
  end

  it 'sets, moves, reads and cancels the signed-in person\'s own reminder' do
    with_modified_env(**switch_on) do
      freeze_time do
        post url, params: { days: 2 }, headers: agent.create_new_auth_token
        expect(response.parsed_body.dig('reminder', 'due_at')).to eq(2.days.from_now.iso8601)
        post url, params: { days: 1 }, headers: agent.create_new_auth_token
        expect(Tolzar::FollowUpReminder.count).to eq(1)

        get url, headers: agent.create_new_auth_token
        expect(response.parsed_body.dig('reminder', 'due_at')).to eq(1.day.from_now.iso8601)
        get url, headers: admin.create_new_auth_token
        expect(response.parsed_body['reminder']).to be_nil

        delete url, headers: agent.create_new_auth_token
        expect(Tolzar::FollowUpReminder.count).to eq(0)
      end
    end
  end

  it 'refuses other day counts and people who cannot see the conversation' do
    with_modified_env(**switch_on) do
      post url, params: { days: 7 }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      post url, params: { days: 1 }, headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(Tolzar::FollowUpReminder.count).to eq(0)
    end
  end

  describe Tolzar::FollowUpRemindersJob do
    it 'notifies the person in-app when due and the customer has not written, then removes the reminder' do
      reminder = Tolzar::FollowUpReminder.remind!(conversation, agent, 1)
      later = Tolzar::FollowUpReminder.remind!(create(:conversation, account: account, inbox: inbox), agent, 3)
      reminder.update_columns(due_at: 1.minute.ago)
      with_modified_env(**switch_on) { described_class.perform_now }

      expect(due_notifications(agent).pluck(:primary_actor_id)).to eq([conversation.id])
      expect(Tolzar::FollowUpReminder.pluck(:id)).to eq([later.id])
    end

    it 'sends nothing when the customer wrote after it was set, and nothing while the switch is off' do
      reminder = Tolzar::FollowUpReminder.remind!(conversation, agent, 1)
      reminder.update_columns(due_at: 1.minute.ago, set_at: 1.day.ago)
      described_class.perform_now
      expect(Tolzar::FollowUpReminder.count).to eq(1)

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      with_modified_env(**switch_on) { described_class.perform_now }
      expect(due_notifications(agent)).to be_empty
      expect(Tolzar::FollowUpReminder.count).to eq(0)
    end
  end

  describe Tolzar::FollowUpRemindersListener do
    def event_for(message)
      Events::Base.new('message.created', Time.zone.now, message: message)
    end

    it 'removes the conversation\'s reminders when the customer writes, not when staff write' do
      Tolzar::FollowUpReminder.remind!(conversation, agent, 2)
      outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      with_modified_env(**switch_on) do
        described_class.instance.message_created(event_for(outgoing))
        expect(Tolzar::FollowUpReminder.count).to eq(1)
        described_class.instance.message_created(event_for(incoming))
      end
      expect(Tolzar::FollowUpReminder.count).to eq(0)
    end
  end

  it 'counts the person\'s reminders due today in the top bar' do
    Tolzar::FollowUpReminder.remind!(conversation, agent, 1).update_columns(due_at: Time.current.utc.beginning_of_day + 1.minute)
    with_modified_env(TOLZAR_TOPBAR_ACCOUNTS: account.id.to_s, **switch_on) do
      get "/api/v1/accounts/#{account.id}/tolzar/briefing", params: { tz: 'UTC' }, headers: agent.create_new_auth_token
      expect(response.parsed_body.dig('now', 'due_today')).to eq(1)
      expect(response.parsed_body.dig('day', 'due').pluck('id')).to eq([conversation.display_id])

      get "/api/v1/accounts/#{account.id}/tolzar/briefing", params: { tz: 'UTC' }, headers: admin.create_new_auth_token
      expect(response.parsed_body.dig('now', 'due_today')).to eq(0)
    end
  end
end
