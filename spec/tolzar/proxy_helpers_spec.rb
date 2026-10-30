require 'rails_helper'

# Tolzar proxy helpers: one team summary for the Dashboard, bulk stage for the Pipeline, audit log paging
# and filters, and an AI agent's versions and duplicate. The brain is stubbed like the other Tolzar specs.
RSpec.describe 'Tolzar proxy helpers', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:brain_agents) { [] }
  let(:brain_audit) { [] }
  let(:gets) { [] }
  let(:posts) { [] }

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain) do |_controller, path|
      gets << path
      { 'ok' => true, 'roles' => {}, 'agents' => brain_agents, 'entries' => brain_audit }
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      posts << [path, body]
      path == '/agents' ? { 'ok' => true, 'agent' => body[:agent].to_h.stringify_keys } : { 'ok' => true }
    end
  end

  def url(path)
    "/api/v1/accounts/#{account.id}/tolzar/#{path}"
  end

  describe 'GET team_summary' do
    let(:inbox) { create(:inbox, account: account) }
    let(:other_inbox) { create(:inbox, account: account) }
    let!(:alpha) { create(:team, account: account, name: 'Alpha') }
    let!(:beta) { create(:team, account: account, name: 'Beta') }

    before do
      create(:conversation, account: account, inbox: inbox, team: alpha)
      create(:conversation, account: account, inbox: inbox, team: alpha, assignee: agent).update_column(:waiting_since, nil)
      create(:conversation, account: account, inbox: other_inbox, team: beta)
      create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, team: beta, status: :resolved)
    end

    it 'counts every team in one response for an administrator' do
      get url('team_summary'), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['totals']).to eq('open' => 4, 'unassigned' => 3, 'waiting' => 3)
      expect(body['teams']).to eq([
                                    { 'id' => alpha.id, 'name' => 'Alpha', 'open' => 2, 'unassigned' => 1, 'waiting' => 1 },
                                    { 'id' => beta.id, 'name' => 'Beta', 'open' => 1, 'unassigned' => 1, 'waiting' => 1 }
                                  ])
      expect(body['no_team']).to eq('open' => 1, 'unassigned' => 1, 'waiting' => 1)
    end

    it 'counts only the conversations an agent may see' do
      create(:inbox_member, user: agent, inbox: inbox)
      get url('team_summary'), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['totals']['open']).to eq(3)
      expect(body['teams'].map { |t| t['open'] }).to eq([2, 0])
    end
  end

  describe 'POST pipeline/bulk_stage' do
    let(:inbox) { create(:inbox, account: account) }
    let(:first) { create(:conversation, account: account, inbox: inbox) }
    let(:second) { create(:conversation, account: account, inbox: inbox) }

    before { first.contact.update!(custom_attributes: { 'deal_value' => 500, 'lifecycle_stage' => 'New Lead' }) }

    it "moves every conversation's contact to the stage, keeps the other attributes and audits each change" do
      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id, second.id], stage: 'Active' },
                                       headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('ok' => true, 'stage' => 'Active', 'updated' => 2)
      expect(first.contact.reload.custom_attributes).to eq('deal_value' => 500, 'lifecycle_stage' => 'Active')
      expect(second.contact.reload.custom_attributes['lifecycle_stage']).to eq('Active')
      audit = Audited::Audit.find_by(auditable: first.contact)
      expect(audit.audited_changes).to eq('lifecycle_stage' => ['New Lead', 'Active'])
      expect([audit.user_id, audit.associated_id]).to eq([admin.id, account.id])
    end

    it "accepts the workspace's own stages only" do
      account.update!(settings: { 'pipeline_stages' => [{ 'key' => 'Lead' }, { 'key' => 'Won' }, { 'key' => 'Lost' }] })
      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id], stage: 'Active' },
                                       headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id], stage: 'Won' },
                                       headers: admin.create_new_auth_token, as: :json
      expect(first.contact.reload.custom_attributes['lifecycle_stage']).to eq('Won')
    end

    it 'refuses more than 200 ids, an empty list and non-integer ids' do
      [Array.new(201) { |i| i + 1 }, [], [first.id.to_s]].each do |ids|
        post url('pipeline/bulk_stage'), params: { conversation_ids: ids, stage: 'Active' },
                                         headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_params')
      end
    end

    it "changes nothing when one conversation is another workspace's or not the agent's" do
      foreign = create(:conversation)
      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id, foreign.id], stage: 'Active' },
                                       headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['conversation_ids']).to eq([foreign.id])
      expect(first.contact.reload.custom_attributes['lifecycle_stage']).to eq('New Lead')

      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id], stage: 'Active' },
                                       headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      create(:inbox_member, user: agent, inbox: inbox)
      post url('pipeline/bulk_stage'), params: { conversation_ids: [first.id], stage: 'Active' },
                                       headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET audit' do
    let(:brain_audit) do
      [{ 'at' => 60.hours.ago.utc.iso8601, 'actor' => "#{admin.id}:#{admin.email}", 'action' => 'agent.save', 'target' => 'a1', 'changes' => [] },
       { 'at' => 5.days.ago.utc.iso8601, 'actor' => 'api', 'action' => 'workspace.export_requested', 'target' => 'chatwoot', 'changes' => [] }]
    end

    before do
      # Only these rows: creating the members wrote audits of their own (AccountUser).
      agent
      Audited::Audit.delete_all
      3.times do |i|
        Audited::Audit.create!(auditable: account, associated: account, user: i.zero? ? agent : admin, action: 'update',
                               audited_changes: { 'name' => ['a', 'b'], 'api_key' => %w[x y] }, created_at: (i + 1).days.ago)
      end
    end

    it 'pages newest first with the total of both logs' do
      get url('audit'), params: { page: 1, per_page: 2 }, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body).to include('ok' => true, 'total' => 5, 'page' => 1, 'per_page' => 2)
      expect(body['entries'].map { |e| e['source'] }).to eq(%w[chatwoot chatwoot])
      expect(body['entries'].first['changes']).to eq('name' => %w[a b])
      get url('audit'), params: { page: 3, per_page: 2 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['entries'].map { |e| e['action'] }).to eq(['workspace.export_requested'])
      expect(gets.last).to eq("/audit?account_id=#{account.id}&limit=1000")
    end

    it 'filters by action, actor and date range' do
      get url('audit'), params: { audit_action: 'account.update', actor: admin.id }, headers: admin.create_new_auth_token
      expect(response.parsed_body['total']).to eq(2)
      get url('audit'), params: { actor: admin.id }, headers: admin.create_new_auth_token
      expect(response.parsed_body['entries'].map { |e| e['action'] }).to eq(%w[account.update agent.save account.update])
      get url('audit'), params: { from: 4.days.ago.to_date.iso8601, to: 2.days.ago.to_date.iso8601 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['total']).to eq(3)
    end

    it 'refuses a page size over 100 and a bad date' do
      get url('audit'), params: { per_page: 101 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      get url('audit'), params: { from: 'yesterday' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'agent versions and duplicate' do
    let(:brain_agents) { [{ 'id' => 'a1', 'name' => 'Sales', 'instructions' => 'Be kind', 'status' => 'active' }] }

    it 'keeps the last 10 saves of an agent, newest first' do
      12.times do |i|
        post url('agents'), params: { agent: { id: 'a1', name: 'Sales', instructions: "v#{i + 1}" } },
                            headers: admin.create_new_auth_token, as: :json
      end
      get url('agents/a1/versions'), headers: admin.create_new_auth_token
      versions = response.parsed_body['versions']
      expect(versions.size).to eq(10)
      expect(versions.first).to include('version' => 12, 'saved_by' => admin.id)
      expect(versions.first['payload']['instructions']).to eq('v12')
      expect(versions.last['version']).to eq(3)
      expect(Tolzar::AgentVersion.where(account: account, agent_id: 'a1').count).to eq(10)
    end

    it 'duplicates the current agent through the brain save, inactive, with a new id' do
      post url('agents/a1/duplicate'), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      path, body = posts.last
      expect(path).to eq('/agents')
      expect(body[:account_id]).to eq(account.id)
      expect(body[:agent]).to include('name' => 'Sales (copy)', 'instructions' => 'Be kind', 'status' => 'inactive')
      expect(body[:agent]['id']).to match(/\Aa[a-z0-9]{7}\z/)
      expect(Tolzar::AgentVersion.where(account: account, agent_id: body[:agent]['id']).count).to eq(1)
    end

    it 'answers 404 for an unknown agent' do
      post url('agents/nope/duplicate'), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(posts).to be_empty
    end

    it 'is for administrators only, and the duplicate for an Owner only' do
      get url('agents/a1/versions'), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      manager = create(:user, account: account, role: :administrator)
      get url('agents/a1/versions'), headers: manager.create_new_auth_token
      expect(response).to have_http_status(:success)
      post url('agents/a1/duplicate'), headers: manager.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(posts).to be_empty
    end
  end
end
