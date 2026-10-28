require 'rails_helper'

# HIGH 2 (full-rel review 2026-10-29): deliveries to the Tolzar brain are retried instead of dropped.
# - Tolzar::Mirror::BrainNotifyJob: connection errors and 408/429/5xx are retried (ATTEMPTS, exponential
#   backoff) with the same X-Chatwoot-Delivery; 2xx and 401 "replayed delivery" are done; any other 4xx
#   is permanent (logged once, not retried).
# - Agent-bot deliveries (Webhooks::Trigger + AgentBots::WebhookJob): Chatwoot retries 429/500 for every
#   bot; for the brain host only, 502/503/504 and an unreachable brain are retried too, 8 times.
RSpec.describe 'Tolzar brain delivery retries' do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe Tolzar::Mirror::BrainNotifyJob do
    let(:hook_url) { 'http://tolzar-brain:8080/hooks/chatwoot' }
    let(:message) { create(:message, message_type: :incoming) }
    let(:env) do
      { BRAIN_WEBHOOK_SECRET: 'tolzar-webhook-secret-0123456789abcdef', TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080',
        TOLZAR_BRAIN_HOOK_URL: hook_url }
    end
    let(:deliveries) { [] }

    before { allow(Tolzar::MirrorConfig).to receive(:mirror_inbox?).and_return(true) }

    # The message is created first, so only this job (and its retries) runs inside perform_enqueued_jobs.
    def run_job
      id = message.id
      with_modified_env(env) { perform_enqueued_jobs { described_class.perform_later(id) } }
    end

    def stub_brain(*responses)
      stub_request(:post, hook_url).with { |req| deliveries << req.headers['X-Chatwoot-Delivery'] }.to_return(*responses)
    end

    it 'backs off exponentially, capped at 5 minutes' do
      expect((1..8).map { |n| described_class::BACKOFF.call(n) }).to eq([10, 20, 40, 80, 160, 300, 300, 300])
    end

    it 'retries a 503 with the same delivery id until the brain answers 2xx' do
      stub_brain({ status: 503 }, { status: 502 }, { status: 200 })
      run_job

      expect(deliveries.size).to eq(3)
      expect(deliveries.uniq.size).to eq(1)
    end

    it 'retries 408 and 429' do
      stub_brain({ status: 408 }, { status: 429 }, { status: 204 })
      run_job

      expect(deliveries.size).to eq(3)
    end

    it 'retries when the brain refuses the connection or times out' do
      stub_request(:post, hook_url)
        .with { |req| deliveries << req.headers['X-Chatwoot-Delivery'] }
        .to_raise(Errno::ECONNREFUSED).then
        .to_timeout.then
        .to_return(status: 200)
      run_job

      expect(deliveries.size).to eq(3)
      expect(deliveries.uniq.size).to eq(1)
    end

    it 're-signs every attempt with a fresh timestamp (the delivery id is what stays)' do
      sigs = []
      stub_request(:post, hook_url).with { |req| sigs << req.headers['X-Chatwoot-Signature'] }
                                   .to_return({ status: 500 }, { status: 200 })
      run_job

      expect(sigs.size).to eq(2)
      expect(sigs).to all(start_with('sha256='))
    end

    it "gives up after #{Tolzar::Mirror::BrainNotifyJob::ATTEMPTS} attempts without raising, and logs it" do
      stub_brain(status: 500)
      allow(Rails.logger).to receive(:warn)

      expect { run_job }.not_to raise_error
      expect(deliveries.size).to eq(described_class::ATTEMPTS)
      expect(Rails.logger).to have_received(:warn).with(/brain notify gave up/).once
    end

    it 'treats 401 "replayed delivery" as done (the brain already has this id)' do
      stub_brain(status: 401, body: '{"detail":"replayed delivery"}', headers: { 'Content-Type' => 'application/json' })
      allow(Rails.logger).to receive(:warn)
      run_job

      expect(deliveries.size).to eq(1)
      expect(Rails.logger).not_to have_received(:warn).with(/tolzar-mirror/)
    end

    it 'treats any other 4xx as permanent: one attempt, logged' do
      [400, 401, 403, 404, 422].each do |status|
        deliveries.clear
        WebMock.reset!
        stub_brain(status: status, body: '{"detail":"bad signature"}')
        allow(Rails.logger).to receive(:warn)
        run_job

        expect(deliveries.size).to eq(1), "status #{status} was retried"
        expect(Rails.logger).to have_received(:warn).with(/brain notify refused .*status=#{status}/)
      end
    end
  end

  describe AgentBots::WebhookJob do
    let(:payload) { { event: 'message_created', id: nil } }

    around { |example| with_modified_env(TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080') { example.run } }

    def run_job(url)
      perform_enqueued_jobs { described_class.perform_later(url, payload, :agent_bot_webhook, secret: nil, delivery_id: 'd-1') }
    end

    it 'configures a Tolzar brain handler with 8 attempts' do
      expect(described_class.rescue_handlers.map(&:first)).to include('Webhooks::Trigger::TolzarBrainRetryableError')
      expect(described_class::TOLZAR_BRAIN_ATTEMPTS).to eq(8)
    end

    context 'when the bot URL is on the brain host' do
      let(:url) { 'http://tolzar-brain:8080/hooks/chatwoot' }

      [502, 503, 504, 500, 429].each do |status|
        it "raises a Tolzar brain retryable error on #{status}" do
          allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new("#{status} Error"))

          expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }
            .to raise_error(Webhooks::Trigger::TolzarBrainRetryableError) { |error| expect(error.status).to eq(status) }
        end
      end

      it 'raises a Tolzar brain retryable error when the brain cannot be reached' do
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('Connection refused - connect(2)'))

        expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }
          .to raise_error(Webhooks::Trigger::TolzarBrainRetryableError) { |error| expect(error.status).to be_nil }
      end

      it 'does not retry another 4xx (e.g. 401 replayed delivery)' do
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('401 Unauthorized'))

        expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }.not_to raise_error
      end

      it 'retries 8 times with the same delivery id, then hands the failure to Chatwoot' do
        calls = []
        allow(Webhooks::Trigger).to receive(:execute) do |_url, _payload, _type, **kwargs|
          calls << kwargs[:delivery_id]
          raise Webhooks::Trigger::TolzarBrainRetryableError.new(status: 503, message: '503 Service Unavailable')
        end
        trigger = instance_double(Webhooks::Trigger, handle_failure: true)
        allow(Webhooks::Trigger).to receive(:new).and_return(trigger)
        allow(Rails.logger).to receive(:warn)

        run_job(url)

        expect(calls).to eq(['d-1'] * 8)
        expect(trigger).to have_received(:handle_failure).with(instance_of(Webhooks::Trigger::TolzarBrainRetryableError)).once
      end
    end

    context 'when the bot URL is any other host' do
      let(:url) { 'https://bots.example.com/hook' }

      it 'keeps Chatwoot behaviour: 503 and an unreachable bot are not retried' do
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable'))
        expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }.not_to raise_error

        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('Connection refused - connect(2)'))
        expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }.not_to raise_error
      end

      it 'keeps Chatwoot behaviour: 500 is the generic retryable error' do
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

        expect { Webhooks::Trigger.execute(url, payload, :agent_bot_webhook) }.to raise_error do |error|
          expect(error.class.name).to eq('Webhooks::Trigger::RetryableError')
        end
      end
    end

    it 'does not retry the brain host for a non-agent-bot webhook' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable'))

      expect { Webhooks::Trigger.execute('http://tolzar-brain:8080/x', payload, :account_webhook) }.not_to raise_error
    end
  end
end
