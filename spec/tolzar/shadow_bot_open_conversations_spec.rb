require 'rails_helper'

# HIGH 3 (full-rel review 2026-10-29): with the Tolzar brain attached to an inbox as its agent bot, new
# conversations used to start as pending (Conversation#set_active_bot_conversation) and sat hidden in
# the Pending tab, while the brain (shadow only) never hands off: it only writes private notes. A bot
# whose outgoing_url host is the brain's host (TOLZAR_BRAIN_URL), or that is flagged
# bot_config['tolzar_shadow'], keeps its conversations open. Any other bot keeps Chatwoot's flow.
RSpec.describe 'Tolzar shadow bot: conversations start open' do
  around { |example| with_modified_env(TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080') { example.run } }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def attach(bot)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    inbox.reload
  end

  describe AgentBot do
    it 'is a Tolzar shadow bot when its outgoing_url is on the brain host' do
      expect(build(:agent_bot, outgoing_url: 'http://tolzar-brain:8080/hooks/chatwoot')).to be_tolzar_shadow
      expect(build(:agent_bot, outgoing_url: 'http://TOLZAR-BRAIN:8080/hooks/chatwoot')).to be_tolzar_shadow
    end

    it 'is a Tolzar shadow bot when flagged in bot_config' do
      expect(build(:agent_bot, outgoing_url: 'https://bots.example.com/hook', bot_config: { 'tolzar_shadow' => true })).to be_tolzar_shadow
    end

    it 'is not one for any other host, a blank or a malformed URL' do
      expect(build(:agent_bot, outgoing_url: 'https://bots.example.com/hook')).not_to be_tolzar_shadow
      expect(build(:agent_bot, outgoing_url: 'http://tolzar-brain.evil.example.com/hook')).not_to be_tolzar_shadow
      expect(build(:agent_bot, outgoing_url: '')).not_to be_tolzar_shadow
      expect(build(:agent_bot, outgoing_url: 'http://exa mple.com/ bad')).not_to be_tolzar_shadow
    end
  end

  context 'when the inbox bot is the Tolzar brain' do
    let(:bot) { create(:agent_bot, account: account, outgoing_url: 'http://tolzar-brain:8080/hooks/chatwoot') }

    before { attach(bot) }

    it 'starts new conversations open, with no bot owner' do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect(conversation.status).to eq('open')
      expect(conversation.ai_assignee).to be_nil
    end

    it 'reopens a resolved conversation as open when the customer writes again' do
      conversation = create(:conversation, account: account, inbox: inbox)
      conversation.resolved!
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)

      expect(conversation.reload.status).to eq('open')
    end

    it 'is not a shadow-bot inbox once the bot link is inactive' do
      inbox.agent_bot_inbox.update!(status: :inactive)
      conversation = create(:conversation, account: account, inbox: inbox.reload)

      expect(conversation.status).to eq('open')
      expect(inbox.tolzar_shadow_bot?).to be(false)
    end
  end

  context 'when the inbox bot is any other bot' do
    let(:bot) { create(:agent_bot, account: account, outgoing_url: 'https://bots.example.com/hook') }

    before { attach(bot) }

    it "keeps Chatwoot's pending flow (the bot owns the conversation until it hands off)" do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect(conversation.status).to eq('pending')
      expect(conversation.ai_assignee).to eq(bot)
    end
  end
end
