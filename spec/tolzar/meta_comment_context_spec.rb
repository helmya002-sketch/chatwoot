require 'rails_helper'

# Tolzar: a Facebook / Instagram comment shows what it was asked under. Tolzar::MetaCommentContextJob reads
# the post (text, type, link, a copied picture) with the page's own token, and the comment a reply answers.
# WebMock refuses every request a test does not stub, so an unexpected Graph call fails it.
RSpec.describe Tolzar::MetaCommentContextJob do
  let(:account) { create(:account) }
  let!(:meta_app) { Tolzar::MetaApp.create!(account: account, app_id: '1234567890123', app_secret: 'a' * 32) }
  let(:channel) do
    Channel::FacebookPage.create!(account: account, page_id: '1001', page_access_token: 'page-token',
                                  user_access_token: 'system-user-token', instagram_id: '1784', tolzar_listen_only: true)
  end
  let!(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:picture) { 'https://scontent.example.com/p.jpg' }

  def ingest(value, platform = 'facebook')
    Tolzar::MetaCommentIngestService.new(channel: channel, platform: platform, value: value).perform
  end

  def comment(extra = {})
    { item: 'comment', verb: 'add', comment_id: '1001_111', post_id: '1001_222', parent_id: '1001_222',
      message: 'How much?', from: { id: 'fan-1', name: 'Fan One' } }.merge(extra)
  end

  before do
    Rails.cache.clear
    allow(SafeFetch).to receive(:fetch).and_yield(
      SafeFetch::Result.new(tempfile: StringIO.new('img'), filename: 'p.jpg', content_type: 'image/jpeg')
    )
  end

  it 'queues the context for a new comment thread, not for each comment' do
    expect { ingest(comment) }.to have_enqueued_job(described_class).once
    expect { ingest(comment(comment_id: '1001_112')) }.not_to have_enqueued_job(described_class)
  end

  it 'stores a Facebook post: text, type, link and a copied picture' do
    graph = stub_request(:get, %r{graph\.facebook\.com/v26\.0/1001_222\?})
            .with(headers: { 'Authorization' => 'Bearer page-token' })
            .to_return(body: { message: 'New Trimix course in May', permalink_url: 'https://www.facebook.com/1001/posts/222',
                               full_picture: picture, status_type: 'added_photos' }.to_json)
    perform_enqueued_jobs { ingest(comment) }

    context = inbox.conversations.sole.additional_attributes.dig('tolzar_comment', 'context')
    expect(context).to include('type' => 'photo', 'text' => 'New Trimix course in May',
                               'permalink' => 'https://www.facebook.com/1001/posts/222')
    expect(context['thumbnail_path']).to start_with('/rails/active_storage/')
    expect(graph).to have_been_made.once
  end

  it 'stores an Instagram reel with its caption and cover picture' do
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/17900000001\?})
      .to_return(body: { caption: 'Wreck dive', permalink: 'https://www.instagram.com/reel/x', media_type: 'VIDEO',
                         media_product_type: 'REELS', thumbnail_url: picture }.to_json)
    perform_enqueued_jobs do
      ingest({ id: '17800000001', text: 'Where?', from: { id: 'igu-1', username: 'fan' }, media: { id: '17900000001' } }, 'instagram')
    end
    context = inbox.conversations.sole.additional_attributes.dig('tolzar_comment', 'context')
    expect(context).to include('type' => 'reel', 'text' => 'Wreck dive', 'permalink' => 'https://www.instagram.com/reel/x')
  end

  it 'marks a post Meta will not show as unavailable, with a link to try' do
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/1001_222\?}).to_return(status: 400, body: { error: { message: 'no' } }.to_json)
    perform_enqueued_jobs { ingest(comment) }
    context = inbox.conversations.sole.additional_attributes.dig('tolzar_comment', 'context')
    expect(context).to include('unavailable' => true, 'permalink' => 'https://www.facebook.com/1001_222')
  end

  it 'quotes a held parent comment natively and reads a foreign one from Meta' do
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/1001_222\?}).to_return(body: { message: 'Post' }.to_json)
    perform_enqueued_jobs { ingest(comment) }
    held = inbox.messages.find_by(source_id: 'comment:1001_111')

    # A second fan answers the first fan's comment we hold: a native reply quote.
    ingest(comment(comment_id: '1001_113', parent_id: '1001_111', from: { id: 'fan-2', name: 'Fan Two' }))
    reply = inbox.messages.find_by(source_id: 'comment:1001_113')
    expect(reply.content_attributes['in_reply_to']).to eq(held.id)

    # A reply to a comment we never received: read from Meta.
    stub_request(:get, %r{graph\.facebook\.com/v26\.0/1001_999\?})
      .to_return(body: { message: 'Is it open?', from: { name: 'Someone' } }.to_json)
    perform_enqueued_jobs { ingest(comment(comment_id: '1001_114', parent_id: '1001_999', from: { id: 'fan-3', name: 'Fan Three' })) }
    foreign = inbox.messages.find_by(source_id: 'comment:1001_114')
    expect(foreign.content_attributes['tolzar_comment_parent']).to eq('text' => 'Is it open?', 'author' => 'Someone')
  end

  it 'reads each post once for several commenters' do
    graph = stub_request(:get, %r{graph\.facebook\.com/v26\.0/1001_222\?}).to_return(body: { message: 'Post' }.to_json)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    perform_enqueued_jobs do
      ingest(comment)
      ingest(comment(comment_id: '1001_115', from: { id: 'fan-4', name: 'Fan Four' }))
    end
    expect(inbox.conversations.count).to eq(2)
    expect(graph).to have_been_made.once
  end

  it 'never sends a crafted id to Graph' do
    expect { Tolzar::MetaGraph.get('/1001_222/../me', {}, 't', 's') }.to raise_error(Tolzar::MetaGraph::Error)
    expect('/1001_222').to match(Tolzar::MetaGraph::SAFE_PATH)
  end
end
