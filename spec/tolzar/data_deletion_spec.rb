require 'rails_helper'

# Tolzar data deletion (queue item C): one person's data, or the whole workspace. Owner-only, typed confirm,
# the brain's rows first, then the Chatwoot side.
RSpec.describe 'Tolzar data deletion', type: :request do
  let(:account) { create(:account, name: 'Delete Me Shop') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Mona Adel', email: 'mona@example.com') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:posts) { [] }
  let(:brain_answer) { { 'ok' => true, 'deleted' => { 'decisions' => 2 } } }

  before do
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:get_from_brain).and_return({ 'ok' => true, 'roles' => {} })
    allow_any_instance_of(Api::V1::Accounts::TolzarController).to receive(:post_to_brain) do |_c, path, body|
      posts << [path, body]
      brain_answer
    end
  end

  def url(path)
    "/api/v1/accounts/#{account.id}/tolzar/data/#{path}"
  end

  describe 'contact erase' do
    it 'erases the brain rows, then the contact with its conversations' do
      post url('contact_erase'), params: { contact_id: contact.id, confirm: 'Mona Adel' }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(posts.first.first).to eq('/dsar/delete')
      expect(Contact.exists?(contact.id)).to be(false)
      # Only the erase's own jobs: the setup's conversation_created event (queued before the erase) is not part of it.
      perform_enqueued_jobs(except: EventDispatcherJob)
      expect(Conversation.exists?(conversation.id)).to be(false)
    end

    it 'needs the name or e-mail typed, and an Owner' do
      post url('contact_erase'), params: { contact_id: contact.id, confirm: 'yes' }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post url('contact_erase'), params: { contact_id: contact.id, confirm: 'Mona Adel' }, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Contact.exists?(contact.id)).to be(true)
    end

    context 'when the brain refuses' do
      let(:brain_answer) { { 'detail' => 'a conversation_id is not this contact\'s; nothing was erased' } }

      it 'keeps the Chatwoot contact' do
        post url('contact_erase'), params: { contact_id: contact.id, confirm: 'mona@example.com' }, headers: owner.create_new_auth_token, as: :json
        expect(response).to have_http_status(:bad_gateway)
        expect(Contact.exists?(contact.id)).to be(true)
      end
    end
  end

  describe 'workspace purge' do
    before do
      allow(Tolzar::BrainClient).to receive(:post).and_return({ 'ok' => true, 'would_delete' => { 'kv' => 3 }, 'deleted' => { 'kv' => 3 } })
    end

    it 'counts on a dry run and changes nothing' do
      post url('workspace_purge'), params: {}, headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('ok' => true, 'dry_run' => true)
      expect(response.parsed_body['chatwoot']).to include('contacts' => 1, 'conversations' => 1)
      expect(Account.exists?(account.id)).to be(true)
    end

    it 'purges only with the workspace name typed, Owner-only' do
      post url('workspace_purge'), params: { dry_run: false, confirm: 'delete' }, headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post url('workspace_purge'), params: { dry_run: false, confirm: 'Delete Me Shop' }, headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      expect do
        post url('workspace_purge'), params: { dry_run: false, confirm: 'Delete Me Shop' }, headers: owner.create_new_auth_token, as: :json
      end.to have_enqueued_job(DeleteObjectJob)
      expect(Tolzar::Subscription.find_by(account_id: account.id).purged_at).to be_present
    end
  end
end

RSpec.describe Tolzar::SubscriptionPurgeJob do
  let(:account) { create(:account) }

  before { allow(Tolzar::BrainClient).to receive(:post).and_return({ 'ok' => true, 'deleted' => {} }) }

  it 'purges a workspace after the 30-day hold, only with enforcement on' do
    sub = Tolzar::Subscription.find_by(account_id: account.id)
    sub.update!(trial_ends_at: 70.days.ago, paused_at: 40.days.ago, purge_after: 10.days.ago)
    described_class.perform_now
    expect(sub.reload.purged_at).to be_nil

    with_modified_env(TOLZAR_BILLING_ENFORCE: 'true') do
      expect { described_class.perform_now }.to have_enqueued_job(DeleteObjectJob)
    end
    expect(sub.reload.purged_at).to be_present
  end

  it 'only stamps the purge date for a workspace that has just paused' do
    sub = Tolzar::Subscription.find_by(account_id: account.id)
    sub.update!(trial_ends_at: 1.day.ago)
    with_modified_env(TOLZAR_BILLING_ENFORCE: 'true') do
      expect { described_class.perform_now }.not_to have_enqueued_job(DeleteObjectJob)
    end
    expect(sub.reload.purge_after).to be_within(1.minute).of(Time.current + 30.days)
  end
end
