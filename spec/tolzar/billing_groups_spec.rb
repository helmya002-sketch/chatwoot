require 'rails_helper'

# Business plan: pooled AI-reply allowance (TOLZAR-POOLED-ALLOWANCE-PLAN-2026-10-30). Only a user who is an
# Owner of EVERY member workspace may create, change or delete a billing group (checked in Rails, before
# the brain is called); at most 5 members; every change is audited on each workspace it touches.
RSpec.describe 'Tolzar billing groups', type: :request do
  let(:controller_class) { Api::V1::Accounts::TolzarController }
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:account_c) { create(:account) }
  # Alice is the first administrator (the account owner) of A and B.
  let!(:alice) { create(:user, account: account_a, role: :administrator) }
  let!(:alice_in_b) { create(:account_user, account: account_b, user: alice, role: :administrator) }
  # Carol owns C, and is only a Manager (a later administrator) in B.
  let!(:carol) do
    create(:user, account: account_c, role: :administrator).tap do |u|
      create(:account_user, account: account_b, user: u, role: :administrator)
    end
  end
  let!(:agent) { create(:user, account: account_a, role: :agent) }
  # A fake brain: groups, the account -> group index, and every POST it received.
  let(:brain) { { groups: {}, index: {}, seq: 0, posts: [] } }

  def brain_status(acct)
    gid = brain[:index][acct]
    group = gid && brain[:groups][gid].merge('id' => gid)
    { 'ok' => true, 'switch_on' => true, 'group' => group, 'used' => 0, 'used_by_member' => {},
      'remaining' => group && group['monthly_ai_replies'], 'period' => { 'month' => '2026-10', 'timezone' => 'UTC' },
      'counting_since' => nil }
  end

  before do
    allow_any_instance_of(controller_class).to receive(:get_from_brain_as) do |_controller, acct, path|
      case path
      when %r{\A/billing_groups} then brain_status(acct)
      when %r{\A/quotas} then { 'ok' => true, 'quota' => { 'daily_calls' => 500, 'monthly_tokens' => nil } }
      else { 'ok' => true, 'roles' => {} }
      end
    end
    allow_any_instance_of(controller_class).to receive(:post_to_brain) do |_controller, path, body|
      body = body.stringify_keys
      brain[:posts] << [path, body]
      if path == '/billing_groups'
        gid = body['id'] || (brain[:seq] += 1)
        brain[:index].delete_if { |_acct, g| g == gid }
        brain[:groups][gid] = body.slice('members', 'monthly_ai_replies', 'tz', 'enabled')
        body['members'].each { |m| brain[:index][m] = gid }
      elsif path == '/billing_groups/delete'
        brain[:groups].delete(body['id'])
        brain[:index].delete_if { |_acct, g| g == body['id'] }
      end
      brain_status(body['account_id'])
    end
  end

  def url(account, suffix = '')
    "/api/v1/accounts/#{account.id}/tolzar/billing_group#{suffix}"
  end

  def save_group(user, account, params)
    post url(account), params: params, headers: user.create_new_auth_token, as: :json
  end

  def billing_audits
    Audited::Audit.where(comment: 'Tolzar billing group')
  end

  it 'lets an Owner of every member create the group, then change its allowance' do
    save_group(alice, account_a, { members: [account_a.id, account_b.id], monthly_ai_replies: 18_000, tz: 'Africa/Cairo', enabled: true })
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['group']).to include('members' => [account_a.id, account_b.id], 'monthly_ai_replies' => 18_000, 'enabled' => true)
    expect(body['can_manage']).to be(true)
    expect(body['members'].map { |m| m['caps'] }).to all(include('daily_calls' => 500))
    record = Tolzar::BillingGroup.find_by!(brain_group_id: body['group']['id'])
    expect(record.owner_user_id).to eq(alice.id)
    expect(record.provider).to be_nil
    expect([account_a.reload, account_b.reload].map(&:tolzar_billing_group_id)).to eq([record.id, record.id])

    save_group(alice, account_a, { members: [account_a.id, account_b.id], monthly_ai_replies: 20_000, tz: 'Africa/Cairo', enabled: true })
    expect(response).to have_http_status(:success)
    expect(brain[:posts].last[1]).to include('id' => record.brain_group_id, 'monthly_ai_replies' => 20_000)
    expect(response.parsed_body['group']['monthly_ai_replies']).to eq(20_000)
  end

  it 'writes an audit entry on every workspace the change touches' do
    expect do
      save_group(alice, account_a, { members: [account_a.id, account_b.id], monthly_ai_replies: 100, enabled: true })
    end.to change { billing_audits.count }.by(2)
    audit = billing_audits.find_by(auditable_type: 'Account', auditable_id: account_b.id)
    expect(audit.user_id).to eq(alice.id)
    expect(audit.audited_changes['tolzar_billing_group'][0]).to be_nil
    expect(audit.audited_changes['tolzar_billing_group'][1]).to include('members' => [account_a.id, account_b.id], 'monthly_ai_replies' => 100)

    expect do
      post url(account_a, '/delete'), headers: alice.create_new_auth_token, as: :json
    end.to change { billing_audits.count }.by(2)
    expect(response).to have_http_status(:success)
    expect(Tolzar::BillingGroup.count).to eq(0)
    expect(account_b.reload.tolzar_billing_group_id).to be_nil
  end

  it 'refuses an Owner of only one member (403) and never calls the brain' do
    save_group(carol, account_c, { members: [account_c.id, account_b.id], monthly_ai_replies: 100 })
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('owner_only')
    expect(brain[:posts]).to be_empty
    expect(billing_audits.count).to eq(0)
  end

  it 'refuses changing or deleting a group the user does not own every member of' do
    save_group(alice, account_a, { members: [account_a.id, account_b.id], monthly_ai_replies: 100 })
    posts = brain[:posts].size
    save_group(carol, account_b, { members: [account_b.id], monthly_ai_replies: 5 })
    expect(response).to have_http_status(:forbidden)
    post url(account_b, '/delete'), headers: carol.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(brain[:posts].size).to eq(posts)
  end

  it 'refuses an agent (403) for reading and for changes' do
    get url(account_a), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    save_group(agent, account_a, { members: [account_a.id], monthly_ai_replies: 100 })
    expect(response).to have_http_status(:forbidden)
    expect(brain[:posts]).to be_empty
  end

  it 'refuses a 6th member' do
    extra = Array.new(4) { create(:account).tap { |acc| create(:account_user, account: acc, user: alice, role: :administrator) } }
    ids = [account_a.id, account_b.id] + extra.map(&:id)
    save_group(alice, account_a, { members: ids, monthly_ai_replies: 100 })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('too_many_members')
    expect(brain[:posts]).to be_empty

    save_group(alice, account_a, { members: ids.first(5), monthly_ai_replies: 100 })
    expect(response).to have_http_status(:success)
  end

  it 'shows a Manager the meter read-only, without workspaces to add' do
    save_group(alice, account_a, { members: [account_a.id, account_b.id], monthly_ai_replies: 100 })
    get url(account_b), headers: carol.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['can_manage']).to be(false)
    expect(body['candidates']).to eq([])
    expect(body).to have_key('counting_since')
    expect(body['members'].find { |m| m['id'] == account_a.id }['name']).to be_nil
  end

  it 'lists only workspaces the Owner owns as ones to add' do
    get url(account_a), headers: alice.create_new_auth_token, as: :json
    expect(response.parsed_body['group']).to be_nil
    expect(response.parsed_body['candidates'].pluck('id')).to eq([account_a.id, account_b.id])
    get url(account_c), headers: carol.create_new_auth_token, as: :json
    expect(response.parsed_body['candidates'].pluck('id')).to eq([account_c.id])
  end
end
