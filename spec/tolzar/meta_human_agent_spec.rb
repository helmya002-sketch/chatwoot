require 'rails_helper'

# Meta HUMAN_AGENT (owner-approved, round 4, c77): a PERSON's Messenger / Instagram reply between 24 hours and 7 days
# after the customer's last message carries the tag and is recorded; the AI, bots and the brain's own user never do;
# with no brain user listed nothing is tagged (fail closed); after 7 days nobody can reply; WhatsApp is unchanged.
RSpec.describe Tolzar::MetaHumanAgent do
  let(:account) { create(:account) }
  let(:person) { create(:user, account: account) }
  let(:brain) { create(:user, account: account) }
  let(:channel) { create(:channel_facebook_page, account: account) }
  let(:inbox) { create(:inbox, channel: channel, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:switches) { { TOLZAR_META_HUMAN_AGENT: account.id.to_s, TOLZAR_BRAIN_USER_IDS: brain.id.to_s } }

  before { stub_request(:post, /graph.facebook.com/) }

  def customer_wrote(ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: ago.ago)
  end

  def reply(sender, **attrs)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: sender }.merge(attrs))
  end

  it "tags a person's reply between 24 hours and 7 days, and records it" do
    with_modified_env(**switches) do
      customer_wrote(2.days)
      message = reply(person)
      expect(described_class.tag?(message)).to be(true)
      described_class.record!(message)
      expect(message.reload.content_attributes['tolzar_human_agent_tag']).to be(true)
    end
  end

  it 'never tags the AI, a bot, the brain user, a private note, or a reply inside 24 hours or after 7 days' do
    with_modified_env(**switches) do
      customer_wrote(2.days)
      expect(described_class.tag?(reply(brain))).to be(false)
      expect(described_class.tag?(reply(create(:agent_bot, account: account)))).to be(false)
      expect(described_class.tag?(reply(person, content_attributes: { 'tolzar_ai' => true }))).to be(false)
      expect(described_class.tag?(reply(person, private: true))).to be(false)
    end
    with_modified_env(**switches) do
      conversation.messages.destroy_all
      customer_wrote(2.hours)
      expect(described_class.tag?(reply(person))).to be(false)
      conversation.messages.destroy_all
      customer_wrote(8.days)
      expect(described_class.tag?(reply(person))).to be(false)
    end
  end

  it 'tags nothing while the switch is off or no brain user is listed (fail closed)' do
    customer_wrote(2.days)
    expect(described_class.tag?(reply(person))).to be(false)
    with_modified_env(TOLZAR_META_HUMAN_AGENT: account.id.to_s) do
      expect(described_class.on?(account.id)).to be(false)
      expect(described_class.tag?(reply(person))).to be(false)
    end
  end

  it 'gives the composer its window, and keeps WhatsApp at 24 hours' do
    customer_wrote(2.days)
    expect(described_class.window(conversation)[:kind]).to eq('closed')
    expect(Conversations::MessageWindowService.new(conversation).can_reply?).to be(false)
    with_modified_env(**switches) do
      expect(described_class.window(conversation)[:kind]).to eq('human_agent')
      expect(Conversations::MessageWindowService.new(conversation).can_reply?).to be(true)
    end

    whatsapp = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    wa_conversation = create(:conversation, inbox: whatsapp.inbox, account: account)
    create(:message, account: account, inbox: whatsapp.inbox, conversation: wa_conversation, message_type: :incoming, created_at: 2.days.ago)
    with_modified_env(**switches) do
      expect(described_class.window(wa_conversation)).to be_nil
      expect(Conversations::MessageWindowService.new(wa_conversation).can_reply?).to be(false)
    end
  end
  # The send path itself (MESSAGE_TAG / HUMAN_AGENT on the Graph call) is in spec/services/facebook and
  # spec/services/instagram, switched to TOLZAR_META_HUMAN_AGENT in this candidate.
end
