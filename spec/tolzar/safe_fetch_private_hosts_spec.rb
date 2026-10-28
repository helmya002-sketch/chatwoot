require 'rails_helper'

# MED 12 (full-rel review 2026-10-29): the Tolzar agent bot must reach the brain on the private Docker
# network without SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true (which opens the private network to every tenant's
# webhooks). SAFE_FETCH_ALLOWED_PRIVATE_HOSTS (default: the host of TOLZAR_BRAIN_URL) lets only those hosts'
# private addresses through; every other private destination stays refused.
RSpec.describe 'SafeFetch allowlisted private hosts' do
  let(:brain_url) { 'http://tolzar-brain:8080/hooks/chatwoot' }
  let(:base_env) { { 'SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'false', 'TOLZAR_BRAIN_URL' => 'http://tolzar-brain:8080' } }

  def post(url)
    SafeFetch.fetch(url, method: :post, body: '{}', validate_content_type: false) { |_result| :ok }
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('tolzar-brain').and_return(['10.0.1.7'])
    allow(Resolv).to receive(:getaddresses).with('ollama').and_return(['10.0.1.8'])
  end

  it 'defaults the allowlist to the TOLZAR_BRAIN_URL host' do
    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => nil)) do
      expect(SafeFetch.allowed_private_hosts).to eq(['tolzar-brain'])
    end
  end

  it 'reads a comma-separated, case-insensitive list, and an empty value allows none' do
    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => ' Tolzar-Brain , 10.0.0.9,')) do
      expect(SafeFetch.allowed_private_hosts).to eq(%w[tolzar-brain 10.0.0.9])
      expect(SafeFetch.allowed_private_host?('TOLZAR-BRAIN')).to be(true)
    end
    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => '')) do
      expect(SafeFetch.allowed_private_hosts).to eq([])
    end
  end

  it 'allows the brain host on its private address with private network access off' do
    stub = stub_request(:post, brain_url).to_return(status: 200, body: '{}')

    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => nil)) do
      expect(post(brain_url)).to eq(:ok)
    end
    expect(stub).to have_been_requested
  end

  it 'refuses any other private host' do
    stub = stub_request(:post, 'http://ollama:11434/api/pull')

    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => nil)) do
      expect { post('http://ollama:11434/api/pull') }.to raise_error(SafeFetch::UnsafeUrlError)
      expect { post('http://10.0.1.7:8080/hooks/chatwoot') }.to raise_error(SafeFetch::UnsafeUrlError)
      expect { post('http://169.254.169.254/latest/meta-data/') }.to raise_error(SafeFetch::UnsafeUrlError)
    end
    expect(stub).not_to have_been_requested
  end

  it 'refuses the brain host too once the allowlist is emptied' do
    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => '')) do
      expect { post(brain_url) }.to raise_error(SafeFetch::UnsafeUrlError)
    end
  end

  it 'refuses a redirect from the brain host to a host outside the allowlist' do
    stub_request(:post, brain_url).to_return(status: 302, headers: { 'Location' => 'http://ollama:11434/api/pull' })
    stub = stub_request(:post, 'http://ollama:11434/api/pull')

    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => nil)) do
      expect { post(brain_url) }.to raise_error(SafeFetch::UnsafeUrlError, /not in SAFE_FETCH_ALLOWED_PRIVATE_HOSTS/)
    end
    expect(stub).not_to have_been_requested
  end

  it 'delivers a Tolzar agent-bot webhook to the brain with private network access off' do
    stub = stub_request(:post, brain_url).to_return(status: 200, body: '{}')

    with_modified_env(base_env.merge('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS' => nil)) do
      expect { Webhooks::Trigger.execute(brain_url, { event: 'message_created' }, :agent_bot_webhook) }.not_to raise_error
    end
    expect(stub).to have_been_requested
  end
end
