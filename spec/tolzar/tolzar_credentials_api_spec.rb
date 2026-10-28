require 'rails_helper'

# Workspace credentials (brain vault.py, security fix C1): keys are write-only fields on the settings
# POSTs. The proxy forwards them to the brain, a Manager can't set them, and they never reach the logs.
RSpec.describe 'Tolzar credentials through the proxy', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:gets) { [] }
  let(:posts) { [] }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      { 'ok' => true, 'roles' => {}, 'credentials' => { 'api_key' => { 'set' => true, 'last4' => '1234', 'source' => 'stored' } } }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true }
    end
  end

  def brain_url(feature)
    "/api/v1/accounts/#{account.id}/tolzar/brain/#{feature}"
  end

  describe 'credentials_prices' do
    it 'reads the price-feed key status for one agent, scoped to this workspace' do
      get brain_url('credentials_prices'), params: { agent_id: 'a1 b' }, headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets.last).to eq("/credentials/prices?account_id=#{account.id}&agent_id=a1+b")
      expect(response.parsed_body.dig('credentials', 'api_key', 'last4')).to eq('1234')
    end

    it 'is Owner-only to set (every POST is, except the preview list)' do
      expect(controller_class::OWNER_POSTS).to include('credentials_prices', 'sms', 'crm_sync', 'commerce')
      expect(controller_class::ADMIN_POSTS).not_to include('credentials_prices')

      post brain_url('credentials_prices'), params: { agent_id: 'a1', api_key: 'sk_live_abcd1234' },
                                            headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('owner_only')
      expect(posts).to be_empty
    end

    it 'forwards the key and clear_credentials to the brain for the Owner, with this workspace id' do
      post brain_url('credentials_prices'), params: { agent_id: 'a1', api_key: 'sk_live_abcd1234', account_id: 999 },
                                            headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/credentials/prices',
                                { 'agent_id' => 'a1', 'api_key' => 'sk_live_abcd1234', 'account_id' => account.id }])

      post brain_url('credentials_prices'), params: { agent_id: 'a1', clear_credentials: ['api_key'] },
                                            headers: owner.create_new_auth_token, as: :json
      expect(posts.last).to eq(['/credentials/prices',
                                { 'agent_id' => 'a1', 'clear_credentials' => ['api_key'], 'account_id' => account.id }])
    end
  end

  it 'forwards the SMS keys as write-only fields' do
    post brain_url('sms'), params: { provider: 'twilio', from: '+4917', api_key: 'tok_9876', account_sid: 'AC123' },
                           headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(posts.last[1]).to include('api_key' => 'tok_9876', 'account_sid' => 'AC123')
  end

  describe 'logging' do
    it 'filters every credential field from logged parameters' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter('api_key' => 'k', 'api_secret' => 's', 'account_sid' => 'AC1', 'provider' => 'twilio')
      expect(filtered).to eq('api_key' => '[FILTERED]', 'api_secret' => '[FILTERED]', 'account_sid' => '[FILTERED]',
                             'provider' => 'twilio')
    end

    it 'does not write the request body to the log when the brain is unreachable' do
      allow_any_instance_of(controller_class).to receive(:post_to_brain).and_call_original
      allow(Tolzar::BrainClient).to receive(:uri).and_raise(StandardError, 'boom sk_live_abcd1234')
      logged = []
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg }

      post brain_url('commerce'), params: { provider: 'shopify', api_key: 'shpat_secret', api_secret: 'woo_secret' },
                                  headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq('brain_unreachable')
      expect(logged.join("\n")).not_to include('shpat_secret', 'woo_secret', 'sk_live_abcd1234')
    end
  end
end
