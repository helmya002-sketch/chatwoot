require 'rails_helper'

# Full-sec review 2026-10-29, brain half (matched with the brain worker s-sec2):
#   M1: TOLZAR_SEND_BRAIN_SECRET=false stops sending X-Tolzar-Brain-Secret on signed requests
#       (default "true" until the brain accepts signed requests without it).
#   H2: TOLZAR_HOOK_KEY_MODE=derived signs the mirror's brain notify with a per-account key
#       HKDF-SHA256(ikm = BRAIN_WEBHOOK_SECRET, salt = "", info = "tolzar-hook-v1:<account_id>", L = 32);
#       default "master" signs with BRAIN_WEBHOOK_SECRET itself.
RSpec.describe 'Tolzar full-sec brain keys (M1, H2)' do
  describe Tolzar::BrainClient do
    let(:secret) { 'tolzar-test-secret-0123456789abcdef' }

    def signed(env)
      req = Net::HTTP::Get.new('/workflows/runs?account_id=7&limit=100')
      with_modified_env({ TOLZAR_BRAIN_SECRET: secret }.merge(env)) do
        described_class.sign(req, 7, ts: 1_700_000_000, nonce: 'fedcba9876543210fedcba9876543210')
      end
      req
    end

    it 'sends the shared secret by default and when TOLZAR_SEND_BRAIN_SECRET=true' do
      expect(signed({})['X-Tolzar-Brain-Secret']).to eq(secret)
      expect(signed(TOLZAR_SEND_BRAIN_SECRET: 'true')['X-Tolzar-Brain-Secret']).to eq(secret)
    end

    it 'stops sending it when TOLZAR_SEND_BRAIN_SECRET=false, the signature unchanged' do
      on = signed(TOLZAR_SEND_BRAIN_SECRET: 'true')
      off = signed(TOLZAR_SEND_BRAIN_SECRET: 'false')
      expect(off['X-Tolzar-Brain-Secret']).to be_nil
      expect(off['X-Tolzar-Sig']).to eq(on['X-Tolzar-Sig'])
      expect(off['X-Tolzar-Sig']).to eq('1b9bd0d5a2ec344b6d1bb3661aa3b31be0178af41014d1376fb79e67a931ebcf')
      %w[X-Tolzar-Account X-Tolzar-Ts X-Tolzar-Body-Sha256 X-Tolzar-Nonce].each { |h| expect(off[h]).to eq(on[h]) }
    end
  end

  describe Tolzar::Mirror::BrainNotifyJob do
    let(:master) { 'tolzar-webhook-secret-0123456789abcdef' }
    let(:hook_url) { 'http://tolzar-brain:8080/hooks/chatwoot' }
    let(:message) { create(:message, message_type: :incoming) }
    let(:env) { { BRAIN_WEBHOOK_SECRET: master, TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080', TOLZAR_BRAIN_HOOK_URL: hook_url } }

    before { allow(Tolzar::MirrorConfig).to receive(:mirror_inbox?).and_return(true) }

    # Vector for the brain side (cross-checked with Python's cryptography HKDF).
    it 'derives the per-account key exactly (HKDF-SHA256 test vector)' do
      key7 = described_class.derive_hook_key(master, 7)
      expect(key7.bytesize).to eq(32)
      expect(key7.unpack1('H*')).to eq('8a3f72629a22c181d85c5554c2fd1bc7a14024a837cd46c793ae139a7c234c45')
      expect(described_class.derive_hook_key(master, 8).unpack1('H*'))
        .to eq('97a4f071719a23d20bd6ca17b820bb3d33ee934a84334c55728b89afe7109c49')
      expect(OpenSSL::HMAC.hexdigest('SHA256', key7, '1700000000.{"event":"message_created","id":1}'))
        .to eq('df233873be2406493bf071b7f70a22dbed960aad831a30802ca3ed94be53b4e8')
    end

    it 'signs with the master key by default (TOLZAR_HOOK_KEY_MODE unset or master)' do
      [{}, { TOLZAR_HOOK_KEY_MODE: 'master' }].each do |mode|
        seen = nil
        stub_request(:post, hook_url).with { |req| seen = req }.to_return(status: 200)
        with_modified_env(env.merge(mode)) { described_class.perform_now(message.id) }
        ts = seen.headers['X-Chatwoot-Timestamp']
        expect(seen.headers['X-Chatwoot-Signature']).to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', master, "#{ts}.#{seen.body}")}")
      end
    end

    it "signs with the message account's derived key when TOLZAR_HOOK_KEY_MODE=derived" do
      seen = nil
      stub_request(:post, hook_url).with { |req| seen = req }.to_return(status: 200)
      with_modified_env(env.merge(TOLZAR_HOOK_KEY_MODE: 'derived')) { described_class.perform_now(message.id) }

      key = OpenSSL::KDF.hkdf(master, salt: '', info: "tolzar-hook-v1:#{message.account_id}", length: 32, hash: 'SHA256')
      ts = seen.headers['X-Chatwoot-Timestamp']
      expect(seen.headers['X-Chatwoot-Signature']).to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{ts}.#{seen.body}")}")
      expect(seen.headers['X-Chatwoot-Signature']).not_to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', master, "#{ts}.#{seen.body}")}")
    end
  end

  describe Tolzar::Mirror::LogSafe do
    it 'logs the error class and a short code, never the message' do
      error = ArgumentError.new('Validation failed: Name Mia +201001234567')
      described = described_class.describe(error)
      expect(described).to match(/\AArgumentError code=\h{8}\z/)
      expect(described).not_to include('Mia', '+2010')
      expect(described_class.code(error)).to eq(Digest::SHA256.hexdigest('Validation failed: Name Mia +201001234567')[0, 8])
    end

    it 'keeps customer content out of the mirror projection error column and log' do
      event = Tolzar::MirrorEvent.create!(tenant: 'aquarius', event_id: SecureRandom.uuid, event_type: 'message.received',
                                          payload: {}, received_at: Time.current)
      allow_any_instance_of(Tolzar::Mirror::Projector).to receive(:call).and_raise(StandardError, 'contact Mia +201001234567')
      allow(Rails.logger).to receive(:error)

      Tolzar::Mirror::ProjectJob.perform_now(event.id)
      expect(event.reload.error).to match(/\AStandardError code=\h{8}\z/)
      expect(Rails.logger).to have_received(:error).with(satisfy { |line| line.exclude?('Mia') && line.include?('StandardError code=') })
    end
  end
end
