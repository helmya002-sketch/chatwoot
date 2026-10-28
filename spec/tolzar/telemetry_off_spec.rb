require 'rails_helper'

# Tolzar: DISABLE_TELEMETRY=true means Chatwoot does not call its hub at all (version ping and
# instance registration), and the version job copes with having no answer.
RSpec.describe 'Tolzar telemetry off' do
  around do |example|
    old = ENV['DISABLE_TELEMETRY']
    ENV['DISABLE_TELEMETRY'] = 'true'
    example.run
  ensure
    ENV['DISABLE_TELEMETRY'] = old
  end

  it 'sends no version ping and no registration' do
    expect(RestClient).not_to receive(:post)
    expect(ChatwootHub.sync_with_hub).to be_nil
    ChatwootHub.register_instance('Acme', 'Owner', 'owner@example.com')
  end

  it 'lets the new-version job run without a hub answer' do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect(RestClient).not_to receive(:post)
    expect { Internal::CheckNewVersionsJob.perform_now }.not_to raise_error
  end
end
