require 'rails_helper'

# B2 (Oracle 30 Oct, first-paying-customer blocker): a new workspace's inboxes get the system brain bot by
# themselves, and brain deliveries are signed with the workspace's own derived key. Off unless
# TOLZAR_AUTO_PROVISION=true.
RSpec.describe Tolzar::BrainProvisioning do
  let(:brain_bot) { create(:agent_bot, account: nil, outgoing_url: 'http://tolzar-brain:8080/hooks/chatwoot') }
  let(:account) { create(:account) }
  let(:env) do
    { TOLZAR_AUTO_PROVISION: 'true', TOLZAR_BRAIN_BOT_ID: brain_bot.id.to_s, TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080',
      BRAIN_WEBHOOK_SECRET: 'master-secret-for-tests' }
  end

  around { |example| with_modified_env(env) { example.run } }

  it 'attaches the system brain bot to a new inbox' do
    inbox = create(:inbox, account: account)
    expect(inbox.reload.agent_bot).to eq(brain_bot)
    expect(inbox.agent_bot_inbox).to be_active
  end

  it 'leaves mirror inboxes and inboxes that already have a bot alone' do
    channel = create(:channel_api, account: account, additional_attributes: { Tolzar::MirrorConfig::MIRROR_INBOX_TAG => true })
    mirror = Inbox.find_by!(channel: channel) # the channel_api factory creates its inbox
    expect(mirror.reload.agent_bot).to be_nil

    other_bot = create(:agent_bot, account: account)
    inbox = create(:inbox, account: account)
    AgentBotInbox.where(inbox: inbox).delete_all
    AgentBotInbox.create!(inbox: inbox, agent_bot: other_bot)
    expect(described_class.attach(inbox)).to be_nil
    expect(inbox.reload.agent_bot).to eq(other_bot)
  end

  it 'never uses an account bot as the brain bot' do
    account_bot = create(:agent_bot, account: account)
    with_modified_env(TOLZAR_BRAIN_BOT_ID: account_bot.id.to_s) do
      expect(create(:inbox, account: account).reload.agent_bot).to be_nil
    end
  end

  it 'does nothing while the switch is off' do
    with_modified_env(TOLZAR_AUTO_PROVISION: 'false') do
      expect(create(:inbox, account: account).reload.agent_bot).to be_nil
    end
  end

  it "signs a brain delivery with the workspace's own derived key, never the bot's secret" do
    key = described_class.signing_key(account.id)
    expect(key.bytesize).to eq(32)
    expect(key).to eq(OpenSSL::KDF.hkdf('master-secret-for-tests', salt: '', info: "tolzar-hook-v1:#{account.id}", length: 32, hash: 'SHA256'))
    expect(described_class.signing_key(account.id + 1)).not_to eq(key)

    payload = { 'event' => 'message_created', 'account' => { 'id' => account.id } }
    expect(Webhooks::Trigger).to receive(:execute).with(brain_bot.outgoing_url, payload, :agent_bot_webhook, secret: key, delivery_id: 'd1')
    AgentBots::WebhookJob.perform_now(brain_bot.outgoing_url, payload, :agent_bot_webhook, secret: nil, delivery_id: 'd1')
  end

  it 'queues brain deliveries without the bot secret, and other bots with theirs' do
    expect(described_class.sign_per_workspace?(brain_bot.outgoing_url)).to be(true)
    expect(described_class.sign_per_workspace?('https://example.com/hook')).to be(false)
    with_modified_env(TOLZAR_AUTO_PROVISION: 'false') do
      expect(described_class.sign_per_workspace?(brain_bot.outgoing_url)).to be(false)
    end
  end
end
