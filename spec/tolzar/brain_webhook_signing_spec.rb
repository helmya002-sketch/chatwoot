require 'rails_helper'

# Webhook to the brain (M3): Chatwoot already signs every agent-bot delivery with the bot's own secret
# (Webhooks::Trigger): X-Chatwoot-Timestamp: <ts>, X-Chatwoot-Signature: "sha256=" + hex HMAC-SHA256(secret,
# "<ts>.<raw body>"), X-Chatwoot-Delivery: <uuid>. The mirror's own brain notify signs the same way with
# BRAIN_WEBHOOK_SECRET, and only towards the brain's host.
RSpec.describe 'Tolzar brain webhook signing' do
  let(:secret) { 'tolzar-webhook-secret-0123456789abcdef' }

  it "pins Chatwoot's agent-bot signature scheme (fixed test vector for the brain)" do
    trigger = Webhooks::Trigger.new('http://tolzar-brain:8080/hooks/chatwoot', {}, :agent_bot_webhook, secret: secret)
    headers = travel_to(Time.zone.at(1_700_000_000)) { trigger.send(:request_headers, '{"event":"message_created","id":1}') }
    expect(headers['X-Chatwoot-Timestamp']).to eq('1700000000')
    expect(headers['X-Chatwoot-Signature']).to eq('sha256=ab1556b94914f2db13c3524ac567ebf93343c596e99208ae8b3bacd24d7a0b39')
  end

  describe Tolzar::Mirror::BrainNotifyJob do
    let(:message) { create(:message, message_type: :incoming) }
    let(:env) { { BRAIN_WEBHOOK_SECRET: secret, TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080', TOLZAR_BRAIN_HOOK_URL: hook_url } }

    before { allow(Tolzar::MirrorConfig).to receive(:mirror_inbox?).and_return(true) }

    context 'when the hook URL is on the brain host' do
      let(:hook_url) { 'http://tolzar-brain:8080/hooks/chatwoot' }

      it 'signs the delivery with BRAIN_WEBHOOK_SECRET' do
        seen = nil
        stub_request(:post, hook_url).with { |req| seen = req }.to_return(status: 200)
        with_modified_env(env) { described_class.perform_now(message.id) }

        ts = seen.headers['X-Chatwoot-Timestamp']
        expect(seen.headers['X-Chatwoot-Signature']).to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{seen.body}")}")
      end

      it 'sends a delivery id (a UUID), the brain accepts each id once' do
        seen = nil
        stub_request(:post, hook_url).with { |req| seen = req }.to_return(status: 200)
        with_modified_env(env) { described_class.perform_now(message.id) }

        expect(seen.headers['X-Chatwoot-Delivery']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      end

      it 'keeps the delivery id stable per job (a retry reuses it), and new per job' do
        ids = []
        stub_request(:post, hook_url).with { |req| ids << req.headers['X-Chatwoot-Delivery'] }.to_return(status: 200)
        job = described_class.new(message.id)
        with_modified_env(env) do
          2.times { job.perform_now }
          described_class.perform_now(message.id)
        end

        expect(ids[0]).to eq(job.job_id)
        expect(ids[1]).to eq(ids[0])
        expect(ids[2]).not_to eq(ids[0])
      end
    end

    context 'when the hook URL is on any other host' do
      let(:hook_url) { 'https://elsewhere.example.com/hooks/chatwoot' }

      it 'never sends the signature (nor anything derived from the secret)' do
        seen = nil
        stub_request(:post, hook_url).with { |req| seen = req }.to_return(status: 200)
        with_modified_env(env) { described_class.perform_now(message.id) }

        expect(seen.headers.keys).not_to include('X-Chatwoot-Signature', 'X-Chatwoot-Timestamp')
      end
    end
  end
end
