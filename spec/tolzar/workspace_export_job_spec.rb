require 'rails_helper'
require 'rubygems/package'

RSpec.describe Tolzar::WorkspaceExportJob do
  let(:account) { create(:account) }

  it 'writes a tar.gz with contacts, conversations, settings and the brain export' do
    contact = create(:contact, account: account, name: 'Mia')
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conversation, account: account, content: 'Hello reef')
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true, 'export' => { 'agents' => [] } })

    described_class.perform_now(account.id)

    blob = described_class.blobs(account.id).first
    files = {}
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(blob.download))) do |tar|
      tar.each { |entry| files[entry.full_name] = entry.read }
    end
    expect(files.keys).to include('contacts.csv', 'conversations.jsonl', 'inboxes.json', 'teams.json', 'brain.json')
    expect(files['contacts.csv']).to include('Mia')
    expect(files['conversations.jsonl']).to include('Hello reef')
  end
end
