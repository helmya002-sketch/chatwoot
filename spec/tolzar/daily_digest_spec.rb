require 'rails_helper'

# Tolzar owner's daily digest (round 4, c89): yesterday's and today's numbers, to the workspace owner only, for
# TOLZAR_DIGEST_ACCOUNTS workspaces only; internal mail, never to a customer.
RSpec.describe Tolzar::DailyDigest do
  let(:account) { create(:account, name: 'Nile Boats') }
  let!(:owner) { create(:user, account: account, role: :administrator, email: 'owner@tolzar.com') }
  let!(:agent) { create(:user, account: account, role: :agent, email: 'agent@tolzar.com') }
  let(:inbox) { create(:inbox, account: account) }

  it "counts yesterday's work and what waits now" do
    travel_to(Time.utc(2026, 11, 3, 8)) do
      yesterday = Time.utc(2026, 11, 2, 10)
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, created_at: yesterday)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: yesterday)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent, created_at: yesterday)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent, private: true,
                       created_at: yesterday)
      ReportingEvent.create!(account_id: account.id, user_id: agent.id, name: 'conversation_resolved', value: 0, created_at: yesterday)

      report = described_class.new(account).report
      expect(report).to include('day' => '2026-11-02', 'new_conversations' => 1, 'customer_messages' => 1, 'team_replies' => 1,
                                'resolved' => 1, 'open_now' => 1)
    end
  end

  it 'mails only the owner, only for listed workspaces' do
    allow(Tolzar::DigestMailer).to receive(:daily).and_call_original
    Tolzar::DailyDigestJob.perform_now
    expect(Tolzar::DigestMailer).not_to have_received(:daily)

    with_modified_env(TOLZAR_DIGEST_ACCOUNTS: account.id.to_s) do
      Tolzar::DailyDigestJob.perform_now
    end
    expect(Tolzar::DigestMailer).to have_received(:daily).with(['owner@tolzar.com'], hash_including('workspace' => 'Nile Boats')).once
  end
end
