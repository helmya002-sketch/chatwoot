require 'rails_helper'

# Tolzar (round 4, c69): the newest version comes from our own release feed, never from Chatwoot's hub.
RSpec.describe Internal::CheckNewVersionsJob do
  subject(:job) { described_class.perform_now }

  before do
    allow(Rails.env).to receive(:production?).and_return(true)
    Redis::Alfred.delete(Redis::Alfred::LATEST_CHATWOOT_VERSION)
  end

  def feed_answers(body)
    result = Struct.new(:tempfile).new(StringIO.new(body))
    allow(SafeFetch).to receive(:fetch).and_yield(result)
  end

  it 'reads the latest version from our release feed' do
    with_modified_env(TOLZAR_RELEASE_FEED_URL: 'https://releases.tolzar.example/latest.json') do
      feed_answers({ version: '1.2.3' }.to_json)
      job
      expect(SafeFetch).to have_received(:fetch).with('https://releases.tolzar.example/latest.json', hash_including(max_bytes: 64.kilobytes))
      expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to eq('1.2.3')
    end
  end

  it 'checks nothing without a feed, never the Chatwoot hub, and ignores a bad answer' do
    allow(ChatwootHub).to receive(:sync_with_hub)
    allow(SafeFetch).to receive(:fetch)
    job
    expect(SafeFetch).not_to have_received(:fetch)
    expect(ChatwootHub).not_to have_received(:sync_with_hub)

    with_modified_env(TOLZAR_RELEASE_FEED_URL: 'https://releases.tolzar.example/latest.json') do
      feed_answers({ version: 'latest; rm -rf' }.to_json)
      job
    end
    expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to be_nil
  end
end
