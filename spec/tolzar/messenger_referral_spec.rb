require 'rails_helper'

# Messenger m.me ref links (brain links.ref_of): the referral is stored as short plain fields
# ({source, type, ref}) on the message it came with (content_attributes.referral) and, for a
# standalone referral event, on the conversation (additional_attributes.referral / referral_ref),
# or kept for the contact's next message when no conversation is open yet.
RSpec.describe 'Tolzar Messenger referral' do
  let(:page_id) { '117172741761305' }
  # Not let!: Channel::FacebookPage subscribes the page after_create_commit (an HTTParty POST to
  # graph.facebook.com), so it must be created after the stub below, not before it.
  let(:facebook_channel) { create(:channel_facebook_page, page_id: page_id) }
  let(:inbox) { facebook_channel.inbox }
  let(:fb_object) { double }
  let(:fixtures) { Rails.root.join('spec/tolzar/fixtures/messenger_referral') }
  let(:pending_key) { "TOLZAR_FB_PENDING_REFERRAL::#{inbox.id}::3383290475046708" }
  let(:shortlink) { { 'source' => 'SHORTLINK', 'type' => 'OPEN_THREAD', 'ref' => '0A1B2C' } }

  def payload(name)
    File.read(fixtures.join("#{name}.json"))
  end

  def parsed(name)
    Integrations::Facebook::MessageParser.new(payload(name))
  end

  def build(name)
    Messages::Facebook::MessageBuilder.new(parsed(name), inbox).perform
  end

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
    allow(fb_object).to receive(:get_object).and_return({ name: 'Jane Dae' }.with_indifferent_access)
    facebook_channel
    Redis::Alfred.delete(pending_key)
  end

  after { Redis::Alfred.delete(pending_key) }

  it 'listens to the referral event and subscribes the page to messaging_referrals' do
    expect(Facebook::Messenger::Bot.send(:hooks)).to have_key(:referral)
    expect(Facebook::Messenger::Subscriptions).to receive(:subscribe)
      .with(hash_including(subscribed_fields: include('messaging_referrals')))
    facebook_channel.subscribe
  end

  describe Integrations::Facebook::MessageParser do
    it 'reads a standalone referral, keeping source, type and ref only' do
      event = parsed('standalone_referral')
      expect(event.standalone_referral?).to be(true)
      expect(event.referral_attributes).to eq(shortlink)
      expect(event.content).to be_nil
    end

    it 'reads the referral inside a postback and inside a message' do
      expect(parsed('get_started_postback').referral_attributes).to eq(shortlink)
      expect(parsed('get_started_postback').standalone_referral?).to be(false)
      expect(parsed('ad_message_referral').referral_attributes)
        .to eq('source' => 'ADS', 'type' => 'OPEN_THREAD', 'ref' => 'AD-SPRING-1')
    end

    it 'keeps nothing without a ref, and caps long values' do
      expect(parsed('referral_without_ref').referral_attributes).to be_nil
      expect(parsed('message_after_referral').referral_attributes).to be_nil
      long = { messaging: { sender: { id: '1' }, recipient: { id: page_id },
                            referral: { ref: 'X' * 500, source: { nested: 1 }, type: 'OPEN_THREAD' } } }.to_json
      attrs = Integrations::Facebook::MessageParser.new(long).referral_attributes
      expect(attrs).to eq('ref' => 'X' * 64, 'type' => 'OPEN_THREAD')
    end
  end

  describe 'messages' do
    it 'stores the Get Started postback referral on the message and the conversation' do
      build('get_started_postback')
      message = inbox.messages.last
      expect(message.content).to eq('Get Started')
      expect(message.content_attributes['referral']).to eq(shortlink)
      expect(message.conversation.additional_attributes).to include('referral' => shortlink, 'referral_ref' => '0A1B2C')
    end

    it 'stores an ad message referral without the ad text or media' do
      build('ad_message_referral')
      referral = inbox.messages.last.content_attributes['referral']
      expect(referral).to eq('source' => 'ADS', 'type' => 'OPEN_THREAD', 'ref' => 'AD-SPRING-1')
    end

    it 'stores no referral on a plain message' do
      build('message_after_referral')
      message = inbox.messages.last
      expect(message.content_attributes).not_to have_key('referral')
      expect(message.conversation.additional_attributes).not_to have_key('referral')
    end

    it 'never puts a referral on an outgoing echo' do
      Messages::Facebook::MessageBuilder.new(parsed('ad_message_referral'), inbox, outgoing_echo: true).perform
      expect(inbox.messages.last.content_attributes).not_to have_key('referral')
    end
  end

  describe 'a standalone referral event' do
    it 'creates no message and stores the code on the open conversation' do
      build('message_after_referral')
      conversation = inbox.conversations.last
      expect { build('standalone_referral') }.not_to change(Message, :count)
      expect(conversation.reload.additional_attributes).to include('referral' => shortlink, 'referral_ref' => '0A1B2C')
    end

    it 'waits for the next message when no conversation is open, then goes on it once' do
      expect { build('standalone_referral') }.not_to change(Message, :count)
      expect(inbox.conversations.count).to eq(0)
      expect(Redis::Alfred.get(pending_key)).to be_present

      build('message_after_referral')
      message = inbox.messages.last
      expect(message.content_attributes['referral']).to eq(shortlink)
      expect(message.conversation.additional_attributes['referral_ref']).to eq('0A1B2C')
      expect(Redis::Alfred.get(pending_key)).to be_nil
    end

    it 'stores nothing for a referral without a ref' do
      expect { build('referral_without_ref') }.not_to change(Message, :count)
      expect(Redis::Alfred.get(pending_key)).to be_nil
    end

    it 'runs through the webhook job end to end' do
      Webhooks::FacebookEventsJob.perform_now(payload('standalone_referral'))
      Webhooks::FacebookEventsJob.perform_now(payload('message_after_referral'))
      expect(inbox.messages.count).to eq(1)
      expect(inbox.messages.last.content_attributes['referral']).to eq(shortlink)
    end
  end
end
