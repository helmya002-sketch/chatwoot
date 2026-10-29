require 'rails_helper'

# A private price file through the proxy: Owner-only upload and restore, .csv/.xlsx up to 1 MB,
# this workspace only, the file sent to the brain base64-encoded and never stored by Rails.
RSpec.describe 'Tolzar private price-file upload', type: :request do
  let(:account) { create(:account, name: 'Blue Reef') }
  let(:other_account) { create(:account, name: 'Other') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:gets) { [] }
  let(:posts) { [] }
  let(:csv) { "item,price,currency\nIntro course,375,EUR\n" }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      { 'ok' => true, 'versions' => [] }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true, 'version' => { 'version' => 1, 'rows' => 1 } }
    end
  end

  def url(path)
    "/api/v1/accounts/#{account.id}/tolzar/#{path}"
  end

  def upload(name, content, user)
    file = Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: name)
    post url('agents/a1/price_upload'), params: { file: file, account_id: other_account.id },
                                        headers: user.create_new_auth_token
  end

  it 'lists versions for every administrator, for this workspace only' do
    get url('agents/a1/price_upload'), headers: manager.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(gets.last).to eq("/agents/a1/price-upload?account_id=#{account.id}")
  end

  it 'refuses a Manager the upload and the restore' do
    upload('prices.csv', csv, manager)
    expect(response).to have_http_status(:forbidden)
    post url('agents/a1/price_upload/restore'), params: { version: 1 }, headers: manager.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(posts).to be_empty
  end

  it 'sends the Owner\'s file to the brain base64-encoded, for this workspace' do
    upload('prices.csv', csv, owner)
    expect(response).to have_http_status(:success)
    path, body = posts.last
    expect(path).to eq('/agents/a1/price-upload')
    expect(body).to include(account_id: account.id, filename: 'prices.csv', format: 'csv')
    expect(Base64.strict_decode64(body[:content_b64])).to eq(csv)
  end

  it 'takes .xlsx and refuses other files and files over 1 MB' do
    upload('prices.xlsx', 'PK fake', owner)
    expect(posts.last[1]).to include(format: 'xlsx')

    posts.clear
    upload('prices.pdf', csv, owner)
    expect(response).to have_http_status(:bad_request)
    upload('prices.csv', 'x' * 1_000_001, owner)
    expect(response).to have_http_status(:bad_request)
    expect(posts).to be_empty
  end

  it 'restores a version for the Owner' do
    post url('agents/a1/price_upload/restore'), params: { version: 2 }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(posts.last).to eq(['/agents/a1/price-upload/restore', { account_id: account.id, version: 2 }])
  end

  it 'refuses an agent id that is not a plain id' do
    get url('agents/a%20b/price_upload'), headers: owner.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(gets).to be_empty
  end
end
