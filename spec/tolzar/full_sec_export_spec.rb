require 'rails_helper'
require 'rubygems/package'

# Full-sec review 2026-10-29.
#   H1: every Tolzar response carries Cache-Control: no-store, private + X-LiteSpeed-Cache-Control: no-cache
#       (whatever its content type), and a workspace export is downloaded by a random token, never by blob id.
#   M6: contacts.csv cells a spreadsheet would run as a formula start with a single quote.
RSpec.describe 'Tolzar full-sec: export download and proxy cache (H1)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar" }

  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true })
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:post_to_brain).and_return({ 'ok' => true })
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true })
  end

  def expect_no_proxy_cache
    expect(response.headers['Cache-Control']).to eq('no-store, private')
    expect(response.headers['X-LiteSpeed-Cache-Control']).to eq('no-cache')
  end

  it 'records each export with a random url-safe token and lists the token, not the blob id' do
    Tolzar::WorkspaceExportJob.perform_now(account.id)
    entry = account.reload.internal_attributes['tolzar_exports'].first
    blob = Tolzar::WorkspaceExportJob.blobs(account.id).first
    expect(entry['id']).to eq(blob.id)
    expect(entry['token']).to match(/\A[A-Za-z0-9_-]{32}\z/)

    get "#{base}/export", headers: admin.create_new_auth_token
    export = response.parsed_body['exports'].first
    expect(export['token']).to eq(entry['token'])
    expect(export).not_to have_key('id')
    expect_no_proxy_cache
  end

  it 'serves the export by token with no-store headers (application/gzip)' do
    Tolzar::WorkspaceExportJob.perform_now(account.id)
    token = account.reload.internal_attributes['tolzar_exports'].first['token']

    get "#{base}/export/download", params: { token: token }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq('application/gzip')
    expect_no_proxy_cache
  end

  it 'no longer serves an export by its blob id, nor by a wrong or empty token' do
    Tolzar::WorkspaceExportJob.perform_now(account.id)
    blob = Tolzar::WorkspaceExportJob.blobs(account.id).first

    get "#{base}/export/download", params: { id: blob.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{base}/export/download", params: { token: 'x' * 32 }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{base}/export/download", params: { token: '' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it "does not serve another account's export by its token" do
    other = create(:account)
    Tolzar::WorkspaceExportJob.perform_now(other.id)
    others_token = other.reload.internal_attributes['tolzar_exports'].first['token']

    get "#{base}/export/download", params: { token: others_token }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'does not serve a token-matched blob whose metadata is not a server-set export of this account' do
    planted = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('planted'), content_type: 'application/gzip',
                                                     filename: 'x.tar.gz', metadata: { 'tolzar_export' => 'true' })
    account.update!(internal_attributes: account.internal_attributes.merge(
      'tolzar_exports' => [{ 'id' => planted.id, 'token' => 'known-token-0123456789abcdef0123' }]
    ))
    get "#{base}/export/download", params: { token: 'known-token-0123456789abcdef0123' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'purges pre-H1 id-only exports on the next export and drops the old key' do
    Tolzar::WorkspaceExportJob.perform_now(account.id)
    legacy = Tolzar::WorkspaceExportJob.blobs(account.id).first
    account.reload.update!(internal_attributes: { 'tolzar_export_blob_ids' => [legacy.id] })

    expect { Tolzar::WorkspaceExportJob.perform_now(account.id) }.to have_enqueued_job(ActiveStorage::PurgeJob)
    attrs = account.reload.internal_attributes
    expect(attrs).not_to have_key('tolzar_export_blob_ids')
    expect(attrs['tolzar_exports'].size).to eq(1)
    expect(attrs['tolzar_exports'].first['id']).not_to eq(legacy.id)
  end

  it 'sets no-store on every Tolzar API response, JSON or not' do
    get "#{base}/branding", headers: admin.create_new_auth_token
    expect_no_proxy_cache

    post "#{base}/export", headers: admin.create_new_auth_token
    expect_no_proxy_cache
  end
end

RSpec.describe TolzarNoProxyCache do
  def call(path, content_type)
    app = ->(_env) { [200, { 'Content-Type' => content_type }, ['x']] }
    described_class.new(app).call(Rack::MockRequest.env_for(path))[1]
  end

  it 'marks any content type under /api/v1/accounts/:id/tolzar/ and /tolzar/ no-store' do
    ['/api/v1/accounts/1/tolzar/export/download', '/tolzar/mirror/status/aquarius', '/tolzar/mcp'].each do |path|
      %w[application/gzip application/octet-stream text/plain application/json].each do |type|
        headers = call(path, type)
        expect(headers['Cache-Control']).to eq('no-store, private')
        expect(headers['X-LiteSpeed-Cache-Control']).to eq('no-cache')
      end
    end
  end

  it 'leaves other non-HTML/JSON responses and static assets alone' do
    expect(call('/api/v1/accounts/1/conversations.csv', 'text/csv')['X-LiteSpeed-Cache-Control']).to be_nil
    expect(call('/vite/assets/app.js', 'application/javascript')['X-LiteSpeed-Cache-Control']).to be_nil
    expect(call('/tolzarish', 'application/gzip')['X-LiteSpeed-Cache-Control']).to be_nil
    expect(call('/api/v1/accounts/1/agents', 'application/json')['X-LiteSpeed-Cache-Control']).to eq('no-cache')
  end
end

RSpec.describe Tolzar::WorkspaceExportJob, '(M6 CSV formula injection)' do
  let(:account) { create(:account) }

  it 'prefixes =, +, -, @, fullwidth @, tab and CR cells with a single quote' do
    expect(described_class.csv_safe('=HYPERLINK("http://x","y")')).to eq(%q('=HYPERLINK("http://x","y")))
    expect(described_class.csv_safe('+20100')).to eq("'+20100")
    expect(described_class.csv_safe('-2+3')).to eq("'-2+3")
    expect(described_class.csv_safe('@SUM(A1)')).to eq("'@SUM(A1)")
    expect(described_class.csv_safe("＠SUM(A1)")).to eq("'＠SUM(A1)")
    expect(described_class.csv_safe("\t=1")).to eq("'\t=1")
    expect(described_class.csv_safe("\r=1")).to eq("'\r=1")
    expect(described_class.csv_safe('Mia = diver')).to eq('Mia = diver')
    expect(described_class.csv_safe(42)).to eq(42)
    expect(described_class.csv_safe(nil)).to be_nil
  end

  it 'writes a contact named like a formula as text in contacts.csv' do
    create(:contact, account: account, name: '=cmd|"/c calc"!A1')
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true })
    described_class.perform_now(account.id)

    files = {}
    blob = described_class.blobs(account.id).first
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(blob.download))) do |tar|
      tar.each { |entry| files[entry.full_name] = entry.read }
    end
    rows = CSV.parse(files['contacts.csv'])
    expect(rows[1][1]).to eq(%q('=cmd|"/c calc"!A1))
  end
end
