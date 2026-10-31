require 'rails_helper'

# Tolzar webhook delivery log (round 4, H2): TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces, administrators; time, event,
# status and duration only (never payload, URL or secret); the last 50 per webhook; nothing recorded while off.
RSpec.describe 'Tolzar webhook delivery log', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:webhook) { create(:webhook, account_id: account.id, inbox_id: nil, url: 'https://hooks.example.com/in?key=secret123') }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/webhooks/#{webhook.id}/deliveries" }
  let(:payload) { { event: 'message_created', content: 'private words' } }
  let(:on) { { TOLZAR_INBOX_TOOLS_ACCOUNTS: account.id.to_s } }

  def deliver
    WebhookJob.perform_now(webhook.url, payload, :account_webhook, secret: nil, delivery_id: 'd1', webhook_id: webhook.id)
  end

  it 'is 404 while the switch is off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'records nothing while the switch is off, and the delivery still goes out' do
    allow(SafeFetch).to receive(:fetch).and_return(nil)
    deliver
    expect(SafeFetch).to have_received(:fetch).once
    expect(Tolzar::WebhookDelivery.count).to eq(0)
  end

  it 'records a success and an HTTP error, and shows them to administrators only' do
    with_modified_env(**on) do
      allow(SafeFetch).to receive(:fetch).and_return(nil)
      deliver
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))
      deliver

      get url, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get url, headers: admin.create_new_auth_token
      rows = response.parsed_body['deliveries']
      expect(rows.pluck('ok')).to eq([false, true])
      expect(rows.first).to include('event' => 'message_created', 'status' => 500, 'error' => 'http')
      expect(rows.first['duration_ms']).to be >= 0
      expect(response.body).not_to include('secret123', 'private words', 'hooks.example.com')
    end
  end

  it 'never stores the URL, the payload or the secret' do
    webhook.update!(secret: 'whsec-test-value')
    with_modified_env(**on) do
      allow(SafeFetch).to receive(:fetch).and_return(nil)
      WebhookJob.perform_now(webhook.url, payload, :account_webhook, secret: webhook.secret, delivery_id: 'd2', webhook_id: webhook.id)
    end
    stored = Tolzar::WebhookDelivery.last.attributes.values.join(' ')
    expect(stored).not_to include('hooks.example.com', 'secret123', 'private words', 'whsec-test-value')
  end

  it 'never breaks a delivery when recording fails' do
    allow(SafeFetch).to receive(:fetch).and_return(nil)
    allow(Tolzar::WebhookDelivery).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'boom')
    with_modified_env(**on) { expect { deliver }.not_to raise_error }
    expect(SafeFetch).to have_received(:fetch).once
  end

  it 'keeps the last 50 per webhook' do
    with_modified_env(**on) do
      allow(SafeFetch).to receive(:fetch).and_return(nil)
      51.times { deliver }
    end
    expect(Tolzar::WebhookDelivery.where(webhook_id: webhook.id).count).to eq(50)
  end

  it 'answers 404 for another workspace webhook' do
    other = create(:webhook, account_id: create(:account).id, inbox_id: nil, url: 'https://other.example.com/in')
    with_modified_env(**on) do
      get "/api/v1/accounts/#{account.id}/tolzar/webhooks/#{other.id}/deliveries", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'passes the webhook id to the job only while the switch is on' do
    webhook
    allow(account).to receive(:api_and_webhooks_enabled?).and_return(true)
    listener = WebhookListener.instance
    expect(WebhookJob).to receive(:perform_later).with(webhook.url, payload, :account_webhook,
                                                       hash_including(webhook_id: webhook.id))
    with_modified_env(**on) { listener.send(:deliver_account_webhooks, payload, account) }
    expect(WebhookJob).to receive(:perform_later).with(webhook.url, payload, :account_webhook,
                                                       hash_excluding(:webhook_id))
    listener.send(:deliver_account_webhooks, payload, account)
  end
end
