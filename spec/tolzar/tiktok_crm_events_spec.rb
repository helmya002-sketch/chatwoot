require 'rails_helper'

# TikTok plan row 7: pipeline outcomes back to TikTok, per-workspace opt-in. Owner-only link with an encrypted
# write-only token and a stage -> event map; an event goes once per contact for a contact from a TikTok lead;
# only the lead id, event name and time are sent.
RSpec.describe 'Tolzar TikTok CRM events' do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  around { |example| with_modified_env(TOLZAR_TIKTOK_CRM_EVENTS: account.id.to_s) { example.run } }

  describe 'the owner link', type: :request do
    let(:url) { "/api/v1/accounts/#{account.id}/tolzar/tiktok_crm" }

    def save(user: owner, **body)
      post url, params: { enabled: true, event_set_id: 'CRM12345', token: 'tt-secret-token',
                          stage_events: { 'Customer Won' => 'CompletePayment' } }.merge(body),
                headers: user.create_new_auth_token, as: :json
    end

    it 'is owner only, keeps the token write-only and checks the stage map' do
      # The token is encrypted at rest: without the ACTIVE_RECORD_ENCRYPTION_* keys this skips (the gate's keyed
      # pass runs it, as encrypted_credentials_spec).
      skip 'ACTIVE_RECORD_ENCRYPTION_* keys are not set' unless Chatwoot.encryption_configured?
      save(user: agent)
      expect(response).to have_http_status(:forbidden)
      save(stage_events: { 'Not a stage' => 'Lead' })
      expect(response).to have_http_status(:unprocessable_entity)
      save
      expect(response.parsed_body.dig('link', 'token')).to eq('set')
      expect(response.body).not_to include('tt-secret-token')
      with_modified_env(TOLZAR_TIKTOK_CRM_EVENTS: '') do
        get url, headers: owner.create_new_auth_token
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'sending' do
    # The link's token is encrypted: without the keys these skip. Declared before let!(:link), so it runs first.
    before { skip 'ACTIVE_RECORD_ENCRYPTION_* keys are not set' unless Chatwoot.encryption_configured? }

    let!(:link) do
      Tolzar::AdPlatformLink.create!(account: account, platform: 'tiktok', enabled: true, event_set_id: 'CRM12345',
                                     token: 'tt-secret-token', stage_events: { 'Customer Won' => 'CompletePayment' })
    end
    let(:contact) do
      create(:contact, account: account, name: 'Sara', email: 'sara@example.com',
                       custom_attributes: { 'lead_source' => 'tiktok', 'lead_id' => 'tt-lead-77', 'lifecycle_stage' => 'New Lead' })
    end

    def change_stage(stage)
      Tolzar::CrmEventsListener.instance.contact_updated(
        Events::Base.new('contact.updated', Time.zone.now,
                         contact: contact, changed_attributes: { 'custom_attributes' => [{ 'lifecycle_stage' => 'New Lead' },
                                                                                         { 'lifecycle_stage' => stage }] })
      )
    end

    it 'queues only a mapped stage for a contact from a TikTok lead' do
      expect { change_stage('Active') }.not_to have_enqueued_job(Tolzar::TiktokCrmEventJob)
      expect { change_stage('Customer Won') }.to have_enqueued_job(Tolzar::TiktokCrmEventJob)
        .with(link.id, contact.id, 'CompletePayment', 'Customer Won')
      contact.update!(custom_attributes: { 'lead_source' => 'website' })
      expect { change_stage('Customer Won') }.not_to have_enqueued_job(Tolzar::TiktokCrmEventJob)
    end

    it 'sends the lead id, event and time only, once per contact and event' do
      Redis::Alfred.delete("tolzar:tiktok_crm:#{link.id}:#{contact.id}:CompletePayment")
      sent = []
      result = Struct.new(:tempfile).new(StringIO.new({ code: 0, message: 'OK' }.to_json))
      allow(SafeFetch).to receive(:fetch) do |url, **opts, &block|
        sent << [url, JSON.parse(opts[:body]), opts[:headers]]
        block.call(result)
      end
      2.times { Tolzar::TiktokCrmEventJob.perform_now(link.id, contact.id, 'CompletePayment', 'Customer Won') }
      expect(sent.size).to eq(1)
      url, body, headers = sent.first
      expect(url).to include('/event/track/')
      expect(body).to include('event_source' => 'crm', 'event_source_id' => 'CRM12345')
      expect(body['data'].first).to include('event' => 'CompletePayment', 'lead' => { 'lead_id' => 'tt-lead-77', 'lead_event_source' => 'tolzar' })
      expect(body.to_json).not_to include('Sara', 'sara@example.com')
      expect(headers['Access-Token']).to eq('tt-secret-token')
      expect(link.reload.sent_count).to eq(1)
    end
  end
end
