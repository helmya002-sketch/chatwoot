require 'rails_helper'

# Tolzar's optional Social tab (owner 30 Oct): with the workspace setting on, public social threads (Facebook /
# Instagram comment threads) are listed only in the Social view; off (the default), one inbox as before.
RSpec.describe 'Tolzar Social tab', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:dm) { create(:conversation, account: account, inbox: inbox) }
  let!(:comment) do
    create(:conversation, account: account, inbox: inbox,
                          additional_attributes: { 'tolzar_comment' => { 'platform' => 'facebook', 'post_id' => '1_2' } })
  end
  let!(:no_attributes) { create(:conversation, account: account, inbox: inbox).tap { |c| c.update_column(:additional_attributes, nil) } }

  def ids(params = {})
    get "/api/v1/accounts/#{account.id}/conversations", params: params, headers: admin.create_new_auth_token
    response.parsed_body['data']['payload'].pluck('id')
  end

  def all_count(params = {})
    get "/api/v1/accounts/#{account.id}/conversations/meta", params: params, headers: admin.create_new_auth_token
    response.parsed_body['meta']['all_count']
  end

  it 'off: one inbox, as before' do
    expect(ids).to contain_exactly(dm.id, comment.id, no_attributes.id)
    expect(ids(conversation_type: 'social')).to eq([comment.id])
  end

  it 'on: comment threads leave the normal views for the Social view, counts included' do
    account.update!(tolzar_social_tab: true)
    expect(ids).to contain_exactly(dm.id, no_attributes.id)
    expect(all_count).to eq(2)
    expect(ids(conversation_type: 'social')).to eq([comment.id])
    expect(all_count(conversation_type: 'social')).to eq(1)
  end

  it 'is saved by an administrator through the account settings' do
    patch "/api/v1/accounts/#{account.id}", params: { tolzar_social_tab: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.reload.tolzar_social_tab).to be(true)
  end
end
