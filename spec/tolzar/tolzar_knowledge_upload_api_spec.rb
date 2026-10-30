require 'rails_helper'

# Knowledge documents through the proxy (readiness row 3): Owner-only, PDF/DOCX/TXT/MD/HTML up to 5 MB, this
# workspace only, the file sent to the brain base64-encoded and never stored by Rails.
RSpec.describe 'Tolzar knowledge document upload', type: :request do
  let(:account) { create(:account, name: 'Blue Reef') }
  let(:other_account) { create(:account, name: 'Other') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:posts) { [] }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain).and_return({ 'ok' => true, 'roles' => {} })
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true, 'source' => body[:filename], 'chunks' => 3 }
    end
  end

  def upload(name, content, user)
    file = Rack::Test::UploadedFile.new(StringIO.new(content), 'application/octet-stream', original_filename: name)
    post "/api/v1/accounts/#{account.id}/tolzar/agents/a1/knowledge_upload",
         params: { file: file, account_id: other_account.id }, headers: user.create_new_auth_token
  end

  it 'sends an Owner\'s document to the brain for this workspace only' do
    upload('pricing.pdf', '%PDF-1.4 test', owner)
    expect(response).to have_http_status(:success)
    path, body = posts.last
    expect(path).to eq('/agents/a1/knowledge-upload')
    expect(body).to include(account_id: account.id, filename: 'pricing.pdf')
    expect(Base64.strict_decode64(body[:content_b64])).to eq('%PDF-1.4 test')
  end

  it 'refuses a Manager, an unsupported type and a file over 5 MB' do
    upload('pricing.pdf', 'x', manager)
    expect(response).to have_http_status(:forbidden)
    upload('photo.png', 'x', owner)
    expect(response).to have_http_status(:bad_request)
    upload('big.txt', 'x' * 5_000_001, owner)
    expect(response.parsed_body['error']).to eq('too_large')
    expect(posts).to be_empty
  end
end
