require 'rails_helper'
require 'rubygems/package'

RSpec.describe Tolzar::WorkspaceExportJob do
  let(:account) { create(:account) }

  it 'writes a tar.gz with contacts, conversations, settings and the brain export' do
    contact = create(:contact, account: account, name: 'Mia')
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conversation, account: account, content: 'Hello reef')
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true, 'export' => { 'agents' => [] } })

    described_class.perform_now(account.id)

    blob = described_class.blobs(account.id).first
    files = {}
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(blob.download))) do |tar|
      tar.each { |entry| files[entry.full_name] = entry.read }
    end
    expect(files.keys).to include('contacts.csv', 'conversations.jsonl', 'inboxes.json', 'teams.json', 'brain.json')
    expect(files['contacts.csv']).to include('Mia')
    expect(files['conversations.jsonl']).to include('Hello reef')
  end

  it 'records the export on the account with server-set metadata' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true })
    described_class.perform_now(account.id)

    blob = described_class.blobs(account.id).first
    expect(account.reload.internal_attributes['tolzar_exports'].map { |e| e['id'] }).to eq([blob.id])
    expect(blob.reload.metadata).to include('tolzar_export' => true, 'account_id' => account.id)
  end

  it 'purges expired exports and drops them from the account list' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true })
    described_class.perform_now(account.id)
    old_id = described_class.blobs(account.id).first.id
    ActiveStorage::Blob.where(id: old_id).update_all(created_at: 8.days.ago)

    described_class.perform_now(account.id)
    ids = account.reload.internal_attributes['tolzar_exports'].map { |e| e['id'] }
    expect(ids).not_to include(old_id)
    expect(ids.size).to eq(1)
  end
end

# H4: an export is never found by filename. Anyone who can upload a file (a widget visitor) picks its
# name, so a planted "tolzar-export-<account>-..." blob must not be listed or served.
RSpec.describe 'Tolzar workspace export lookup (H4)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true })
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:post_to_brain).and_return({ 'ok' => true })
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true })
  end

  def plant(metadata = {})
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('planted'), content_type: 'application/gzip',
                                           filename: "#{Tolzar::WorkspaceExportJob.prefix(account.id)}20261028T000000Z.tar.gz",
                                           metadata: metadata)
  end

  it 'does not list or serve a planted blob with a matching filename' do
    planted = plant
    get "/api/v1/accounts/#{account.id}/tolzar/export", headers: admin.create_new_auth_token
    expect(response.parsed_body['exports']).to eq([])

    get "/api/v1/accounts/#{account.id}/tolzar/export/download", params: { id: planted.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it "does not serve a blob recorded for the account whose metadata isn't a server-set export" do
    planted = plant('tolzar_export' => 'true', 'account_id' => account.id.to_s)
    account.update!(internal_attributes: account.internal_attributes.merge(
      'tolzar_exports' => [{ 'id' => planted.id, 'token' => 'planted-token-0123456789abcdef01' }]
    ))
    get "/api/v1/accounts/#{account.id}/tolzar/export/download", params: { token: 'planted-token-0123456789abcdef01' },
                                                                 headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it "lists and serves the job's own export, and not another account's" do
    Tolzar::WorkspaceExportJob.perform_now(account.id)
    other = create(:account)
    Tolzar::WorkspaceExportJob.perform_now(other.id)
    own = Tolzar::WorkspaceExportJob.blobs(account.id).first
    others = Tolzar::WorkspaceExportJob.blobs(other.id).first

    get "/api/v1/accounts/#{account.id}/tolzar/export", headers: admin.create_new_auth_token
    own_token = Tolzar::WorkspaceExportJob.tokens(account.id)[own.id]
    others_token = Tolzar::WorkspaceExportJob.tokens(other.id)[others.id]
    expect(response.parsed_body['exports'].map { |e| e['token'] }).to eq([own_token])

    get "/api/v1/accounts/#{account.id}/tolzar/export/download", params: { token: own_token }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    get "/api/v1/accounts/#{account.id}/tolzar/export/download", params: { token: others_token }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
