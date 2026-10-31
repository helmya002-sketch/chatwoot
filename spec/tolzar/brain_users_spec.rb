require 'rails_helper'

# Tolzar brain read user (round 4, c100): with TOLZAR_BRAIN_USER_IDS set, a new inbox gets the read user as a member
# (only a user of that workspace), and the read user is never assignable; unset, nothing changes.
RSpec.describe Tolzar::BrainUsers do
  let(:account) { create(:account) }
  let!(:brain) { create(:user, account: account, role: :agent) }
  let!(:outsider) { create(:user) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  it 'does nothing while unset' do
    inbox = create(:inbox, account: account)
    expect(inbox.inbox_members.count).to eq(0)
    create(:inbox_member, inbox: inbox, user: brain)
    expect(inbox.reload.assignable_agents).to eq([brain])
  end

  it 'adds the read user to new inboxes of its workspace only, and never assigns it' do
    with_modified_env(TOLZAR_BRAIN_USER_IDS: "#{brain.id},#{outsider.id}") do
      inbox = create(:inbox, account: account)
      expect(inbox.inbox_members.pluck(:user_id)).to eq([brain.id])

      create(:inbox_member, inbox: inbox, user: agent)
      expect(inbox.reload.assignable_agents).to eq([agent])

      described_class.add_to_inbox(inbox)
      expect(inbox.inbox_members.where(user_id: brain.id).count).to eq(1)
    end
  end

  it 'keeps the read user out of round robin' do
    with_modified_env(TOLZAR_BRAIN_USER_IDS: brain.id.to_s) do
      inbox = create(:inbox, account: account, enable_auto_assignment: true)
      create(:inbox_member, inbox: inbox, user: agent)
      conversation = create(:conversation, account: account, inbox: inbox)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return(brain.id.to_s => 'online', agent.id.to_s => 'online')

      service = AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: [brain.id, agent.id])
      expect(service.send(:allowed_online_agent_ids)).to eq([agent.id.to_s])
    end
  end
end
