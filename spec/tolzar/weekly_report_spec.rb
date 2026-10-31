require 'rails_helper'

# Tolzar weekly staff report (round 4, c98): the last 7 days per person and per inbox, to the workspace's
# administrators only, for TOLZAR_WEEKLY_REPORT_ACCOUNTS workspaces only; internal mail, never to a customer.
RSpec.describe Tolzar::WeeklyReport do
  let(:account) { create(:account, name: 'Nile Boats') }
  let!(:admin) { create(:user, account: account, role: :administrator, email: 'owner@tolzar.com', name: 'Amal') }
  let!(:agent) { create(:user, account: account, role: :agent, email: 'agent@tolzar.com', name: 'Omar') }
  let!(:inbox) { create(:inbox, account: account, name: 'Website') }

  it 'reports the week per person and per inbox' do
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)

    report = described_class.new(account).report
    expect(report['workspace']).to eq('Nile Boats')
    expect(report['people'].first).to include('name' => 'Omar', 'replies' => 1)
    expect(report['inboxes'].first).to include('name' => 'Website', 'conversations' => 1, 'incoming' => 1)
  end

  it 'mails only the administrators, only for listed workspaces' do
    allow(Tolzar::DigestMailer).to receive(:weekly).and_call_original
    Tolzar::WeeklyReportJob.perform_now
    expect(Tolzar::DigestMailer).not_to have_received(:weekly)

    with_modified_env(TOLZAR_WEEKLY_REPORT_ACCOUNTS: account.id.to_s) do
      Tolzar::WeeklyReportJob.perform_now
    end
    expect(Tolzar::DigestMailer).to have_received(:weekly).with(['owner@tolzar.com'], hash_including('workspace' => 'Nile Boats')).once
  end
end
