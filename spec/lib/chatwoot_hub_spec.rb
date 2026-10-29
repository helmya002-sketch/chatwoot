require 'rails_helper'

# Tolzar: ChatwootHub never calls Chatwoot's servers (owner rule, 29 Oct 2026: never depend on Chatwoot).
describe ChatwootHub do
  before { allow(RestClient).to receive(:post) }

  it 'generates installation identifier' do
    installation_identifier = described_class.installation_identifier
    expect(installation_identifier).not_to be_nil
    expect(described_class.installation_identifier).to eq installation_identifier
  end

  it 'does not ping for versions, register the instance or send events' do
    expect(described_class.sync_with_hub).to be_nil
    expect(described_class.register_instance('Acme', 'Owner', 'owner@example.com')).to be_nil
    expect(described_class.emit_event('sample_event', { 'k' => 'v' })).to be_nil
    expect(RestClient).not_to have_received(:post)
  end

  it 'has no push relay: mobile push needs the install's own Firebase project' do
    expect(described_class.send_push({ token: 'x' })).to be_nil
    expect { described_class.send_push_with_response({ token: 'x' }) }.to raise_error(/FIREBASE_PROJECT_ID/)
    expect(RestClient).not_to have_received(:post)
  end

  it 'makes no request to any chatwoot.com host' do
    described_class.sync_with_hub
    described_class.send_push({ token: 'x' })
    expect(a_request(:any, /chatwoot\.com/)).not_to have_been_made
  end
end
