require 'rails_helper'

# TikTok plan row 2: comments on the business's own videos into the TikTok inbox, read-only toward TikTok,
# only for TOLZAR_TIKTOK_COMMENTS workspaces; a staff reply in a comment thread is never sent as a DM.
RSpec.describe Tolzar::TiktokCommentIngestService do
  let(:channel) { create(:channel_tiktok, business_id: 'biz-1') }
  let(:inbox) { channel.inbox }
  let(:video) { { 'item_id' => 'v1', 'caption' => 'Our spring sale', 'share_url' => 'https://www.tiktok.com/@shop/video/v1' } }

  def ingest(comment)
    described_class.new(channel: channel, video: video, comment: comment).perform
  end

  it 'makes one labelled conversation per commenter per video, with the video as context' do
    ingest('comment_id' => 'c1', 'text' => 'How much is it?', 'user_id' => 'u1', 'display_name' => 'Sara', 'create_time' => 1)
    ingest('comment_id' => 'c2', 'text' => 'And delivery?', 'user_id' => 'u1', 'display_name' => 'Sara', 'create_time' => 2)
    conversation = inbox.conversations.sole
    expect(conversation.label_list).to eq(['comment'])
    expect(conversation.additional_attributes['tolzar_comment']).to include('platform' => 'tiktok', 'post_id' => 'v1',
                                                                            'post_text' => 'Our spring sale')
    expect(conversation.messages.incoming.pluck(:content)).to eq(['How much is it?', 'And delivery?'])
    expect(conversation.contact.name).to eq('Sara')
  end

  it 'ignores a comment seen again, and threads the business reply under the comment it answers' do
    ingest('comment_id' => 'c1', 'text' => 'Hi', 'user_id' => 'u1')
    ingest('comment_id' => 'c1', 'text' => 'Hi', 'user_id' => 'u1')
    ingest('comment_id' => 'c9', 'text' => 'Thanks, check your DMs', 'user_id' => 'biz-1', 'parent_comment_id' => 'c1')
    conversation = inbox.conversations.sole
    expect(conversation.messages.incoming.count).to eq(1)
    reply = conversation.messages.outgoing.sole
    expect(reply.content).to eq('Thanks, check your DMs')
    expect(reply.content_attributes['in_reply_to']).to eq(conversation.messages.incoming.first.id)
  end

  it 'never answers a comment thread by DM' do
    ingest('comment_id' => 'c1', 'text' => 'Hi', 'user_id' => 'u1')
    conversation = inbox.conversations.sole
    message = create(:message, conversation: conversation, account: conversation.account, inbox: inbox,
                               message_type: :outgoing, content: 'Hello!')
    expect(Tiktok::Client).not_to receive(:new)
    Tiktok::SendOnTiktokService.new(message: message).perform
    expect(message.reload.status).to eq('failed')
  end
end

RSpec.describe Tolzar::TiktokCommentsPollJob do
  let!(:channel) { create(:channel_tiktok, business_id: 'biz-1') }
  let(:client) { instance_double(Tolzar::TiktokComments::Client) }

  before do
    allow(Channel::Tiktok).to receive(:where).and_call_original
    allow_any_instance_of(Channel::Tiktok).to receive(:validated_access_token).and_return('tok') # rubocop:disable RSpec/AnyInstance
    allow(Tolzar::TiktokComments::Client).to receive(:new).and_return(client)
    allow(client).to receive(:videos).and_return([{ 'item_id' => 'v1' }])
    allow(client).to receive(:comments).with('v1').and_return(
      [{ 'comment_id' => 'c2', 'text' => 'second', 'user_id' => 'u1', 'create_time' => 20 },
       { 'comment_id' => 'c1', 'text' => 'first', 'user_id' => 'u1', 'create_time' => 10 }]
    )
  end

  it 'does nothing while TOLZAR_TIKTOK_COMMENTS is empty' do
    described_class.perform_now
    expect(Tolzar::TiktokComments::Client).not_to have_received(:new)
  end

  it 'reads the comments oldest first for the listed workspaces' do
    with_modified_env(TOLZAR_TIKTOK_COMMENTS: channel.account_id.to_s) do
      described_class.perform_now
    end
    expect(channel.inbox.messages.incoming.order(:id).pluck(:content)).to eq(%w[first second])
  end
end
