require 'rails_helper'

# Readiness row 23: a workspace can never read or write another workspace's brain data through the proxy.
# Every generic brain route (BRAIN_GETS / BRAIN_POSTS) is driven by an Owner of workspace A who names workspace B
# in every place a browser could put it; the brain must only ever be asked about A. A user of A who calls B's
# URLs gets nothing from the brain at all.
RSpec.describe 'Tolzar brain proxy tenant isolation', type: :request do
  let(:account) { create(:account, name: 'Workspace A') }
  let(:other) { create(:account, name: 'Workspace B') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:calls) { [] }

  before do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'ok' => true, 'roles' => {} })
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_c, path|
      calls << [:get, path]
      { 'ok' => true, 'roles' => {} }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_c, path, body|
      calls << [:post, path, body]
      { 'ok' => true }
    end
  end

  def brain_url(acct, feature)
    "/api/v1/accounts/#{acct.id}/tolzar/brain/#{feature}"
  end

  it 'asks the brain only about the URL\'s own workspace on every GET route' do
    controller_class::BRAIN_GETS.each_key do |feature|
      get brain_url(account, feature), params: { account_id: other.id, accountId: other.id },
                                       headers: owner.create_new_auth_token
      expect(response.status).to be < 500, "#{feature}: #{response.status}"
    end
    gets = calls.select { |c| c.first == :get }
    expect(gets).not_to be_empty
    gets.each do |_, path|
      ids = path.scan(/account_id=(\d+)/).flatten
      expect(ids).to eq([account.id.to_s]), "#{path} names #{ids}"
    end
  end

  it 'writes only to the URL\'s own workspace on every POST route' do
    controller_class::BRAIN_POSTS.each_key do |feature|
      post brain_url(account, feature), params: { account_id: other.id, 'account' => { 'id' => other.id } },
                                        headers: owner.create_new_auth_token, as: :json
      expect(response.status).to be < 500, "#{feature}: #{response.status}"
    end
    posts = calls.select { |c| c.first == :post }
    expect(posts).not_to be_empty
    posts.each do |_, path, body|
      body = body.to_h.stringify_keys
      expect(body['account_id']).to eq(account.id), "#{path} wrote to #{body['account_id']}"
      expect(path).not_to include("account_id=#{other.id}")
    end
  end

  it "never reaches the brain for a workspace the user doesn't belong to" do
    %w[usage roi scoreboard qa recovery branding compliance].each do |feature|
      get brain_url(other, feature), headers: owner.create_new_auth_token
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
    end
    post brain_url(other, 'branding'), params: { product_name: 'Hijack' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
    expect(calls).to be_empty
  end
end
