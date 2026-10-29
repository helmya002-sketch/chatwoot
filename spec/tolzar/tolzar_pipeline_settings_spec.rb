require 'rails_helper'

# The workspace's pipeline (Tolzar::PipelineSettings) in account.settings: every administrator reads
# it, only the Owner changes it, bad values are refused with the reason, an empty value clears a key.
RSpec.describe 'Tolzar pipeline settings', type: :request do
  let(:account) { create(:account) }
  # The first administrator is the account owner (Tolzar::AccountOwner); the second is a Manager.
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/pipeline" }

  # A Manager's role is looked up in the brain (Tolzar roles); no brain in tests.
  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'roles' => {} })
  end

  it 'saves stages, stage fields, the deal value field and currency for the Owner' do
    settings = { pipeline_stages: [{ key: 'New', label: 'New' }, 'Qualified', { key: 'Won', tone: 'teal' }],
                 stage_attributes: %w[lifecycle_stage imported_stage], deal_value_attribute: 'deal_value',
                 deal_currency: 'usd' }
    post url, params: { settings: settings }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    saved = account.reload.settings
    expect(saved['pipeline_stages'].pluck('key')).to eq(%w[New Qualified Won])
    expect(saved['pipeline_stages'].last).to eq('key' => 'Won', 'label' => 'Won', 'tone' => 'teal')
    expect(saved).to include('stage_attributes' => %w[lifecycle_stage imported_stage],
                             'deal_value_attribute' => 'deal_value', 'deal_currency' => 'USD')

    get url, headers: manager.create_new_auth_token, as: :json
    expect(response.parsed_body['settings']['deal_currency']).to eq('USD')
  end

  it 'refuses bad values with the reason and keeps what was stored' do
    account.update!(settings: (account.settings || {}).merge('deal_currency' => 'EUR'))
    post url, params: { settings: { pipeline_stages: ['Only one'], stage_attributes: ['Bad Key'], deal_currency: 'euro' } },
              headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body['detail'].join(' ')).to include('pipeline_stages', 'stage_attributes', 'deal_currency')
    expect(account.reload.settings['deal_currency']).to eq('EUR')
  end

  it 'clears a key when it is sent empty' do
    account.update!(settings: (account.settings || {}).merge('deal_currency' => 'EUR', 'auto_resolve_after' => 60))
    post url, params: { settings: { deal_currency: '' } }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.reload.settings).not_to have_key('deal_currency')
    expect(account.settings['auto_resolve_after']).to eq(60)
  end

  it 'is Owner-only for changes' do
    post url, params: { settings: { deal_currency: 'USD' } }, headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(account.reload.settings.to_h).not_to have_key('deal_currency')
  end
end
