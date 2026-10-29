require 'rails_helper'

# A workspace's conversation retention (Tolzar::ConversationRetention): off unless the Owner sets a
# period; past it, conversations go with their messages; other workspaces and the respond.io mirror
# inbox are never touched.
RSpec.describe Tolzar::ConversationRetention do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2028-11-01 03:15') }
  let(:brain_calls) { [] }

  # The brain is told what went (POST /retention/forget); no brain in tests.
  before do
    allow(Tolzar::BrainClient).to receive(:post) { |path, body, **| brain_calls << [path, body] && { 'ok' => true } }
  end

  def conversation_at(time, in_inbox = inbox)
    create(:conversation, account: account, inbox: in_inbox).tap { |c| c.update_columns(last_activity_at: time) }
  end

  it 'does nothing until a period is set' do
    old = conversation_at(now - 5.years)
    expect(described_class.days(account)).to be_nil
    expect(described_class.new(account, now: now).purge).to eq(0)
    expect(Conversation.exists?(old.id)).to be(true)
  end

  it 'deletes only conversations past the period, never the mirror inbox, never another workspace' do
    account.update!(settings: (account.settings || {}).merge(described_class::KEY => 730))
    old = conversation_at(now - 731.days)
    recent = conversation_at(now - 700.days)
    mirror_channel = create(:channel_api, account: account,
                                          additional_attributes: { Tolzar::MirrorConfig::MIRROR_INBOX_TAG => true })
    mirror = create(:inbox, account: account, channel: mirror_channel)
    mirrored = conversation_at(now - 5.years, mirror)
    other = create(:conversation)
    other.update_columns(last_activity_at: now - 5.years)

    expect(described_class.purge_all(now: now)).to eq(account.id => 1)
    expect(Conversation.exists?(old.id)).to be(false)
    expect(Conversation.exists?(recent.id)).to be(true)
    expect(Conversation.exists?(mirrored.id)).to be(true)
    expect(Conversation.exists?(other.id)).to be(true)
    # The brain forgets the same conversations, by the display id its webhooks use.
    expect(brain_calls).to eq([['/retention/forget', { account_id: account.id, conversation_ids: [old.display_id] }]])
  end

  it 'counts a conversation with no activity date from its creation, and one failing workspace does not stop the rest' do
    account.update!(settings: (account.settings || {}).merge(described_class::KEY => 730))
    undated = create(:conversation, account: account, inbox: inbox)
    undated.update_columns(last_activity_at: nil, created_at: now - 3.years)
    broken = create(:account)
    broken.update!(settings: (broken.settings || {}).merge(described_class::KEY => 730))
    allow_any_instance_of(described_class).to receive(:purge).and_wrap_original do |m, *args|
      raise 'boom' if m.receiver.instance_variable_get(:@account).id == broken.id

      m.call(*args)
    end
    result = described_class.purge_all(now: now)
    expect(result[broken.id]).to be_nil
    expect(result[account.id]).to eq(1)
    expect(Conversation.exists?(undated.id)).to be(false)
  end

  it 'still deletes when the brain cannot be told' do
    allow(Tolzar::BrainClient).to receive(:post).and_raise(Errno::ECONNREFUSED)
    account.update!(settings: (account.settings || {}).merge(described_class::KEY => 730))
    old = conversation_at(now - 800.days)
    expect(described_class.new(account, now: now).purge).to eq(1)
    expect(Conversation.exists?(old.id)).to be(false)
  end

  it 'ignores a period outside 365 to 3650 days' do
    account.update!(settings: (account.settings || {}).merge(described_class::KEY => 30))
    expect(described_class.days(account)).to be_nil
  end

  describe 'settings API', type: :request do
    let!(:owner) { create(:user, account: account, role: :administrator) }
    let!(:manager) { create(:user, account: account, role: :administrator) }
    let(:url) { "/api/v1/accounts/#{account.id}/tolzar/conversation_retention" }

    # A Manager's role is looked up in the brain (Tolzar roles); no brain in tests.
    before do
      allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'roles' => {} })
    end

    it 'lets the Owner set and clear it, refuses bad values and Managers' do
      post url, params: { days: 730 }, headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('ok' => true, 'days' => 730)
      expect(account.reload.settings[described_class::KEY]).to eq(730)
      audit = Audited::Audit.where(auditable: account, comment: 'Tolzar conversation retention').last
      expect(audit.audited_changes).to eq(described_class::KEY => [nil, 730])
      expect(audit.user).to eq(owner)
      post url, params: { days: 10 }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
      post url, params: { days: 900 }, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post url, params: { days: '' }, headers: owner.create_new_auth_token, as: :json
      expect(account.reload.settings).not_to have_key(described_class::KEY)
      get url, headers: manager.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('days' => nil, 'expired' => 0)
    end
  end
end
