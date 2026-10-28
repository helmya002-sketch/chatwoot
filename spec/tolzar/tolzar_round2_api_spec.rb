require 'rails_helper'

# Round 2 polish through the admin proxy: the documents switch (Off / Shadow) is allow-listed,
# its write is Owner-only, and the media settings carry the video fields through unchanged.
RSpec.describe 'Tolzar API round 2', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:role) { 'owner' }
  let(:gets) { [] }
  let(:posts) { [] }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      { 'ok' => true, 'role' => role }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      { 'ok' => true }
    end
  end

  def brain_url(feature)
    "/api/v1/accounts/#{account.id}/tolzar/brain/#{feature}"
  end

  describe 'documents' do
    it 'reads the switch from the brain, scoped to this workspace' do
      get brain_url('documents'), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(gets.last).to eq("/documents?account_id=#{account.id}")
    end

    it 'posts the mode with the URL workspace, never one from the body' do
      post brain_url('documents'), params: { mode: 'shadow', account_id: other_account.id },
                                   headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts).to eq([['/documents', { 'mode' => 'shadow', 'account_id' => account.id }]])
    end

    it 'refuses agents' do
      get brain_url('documents'), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when the member is a Manager' do
      let(:role) { 'manager' }

      it 'lets them read but not change the switch' do
        get brain_url('documents'), headers: admin.create_new_auth_token
        expect(response).to have_http_status(:success)
        post brain_url('documents'), params: { mode: 'shadow' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('owner_only')
        expect(posts).to be_empty
      end
    end
  end

  describe 'media video' do
    it 'passes video and video_frames to the brain unchanged' do
      post brain_url('media'), params: { voice: 'off', images: 'shadow', video: 'shadow', video_frames: 3 },
                               headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.last).to eq(['/media', { 'voice' => 'off', 'images' => 'shadow', 'video' => 'shadow',
                                            'video_frames' => 3, 'account_id' => account.id }])
    end
  end
end
