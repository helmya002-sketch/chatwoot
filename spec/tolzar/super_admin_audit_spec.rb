require 'rails_helper'

# Tolzar Control Center audit: every super-admin change and sign-in attempt, field names only, never values.
RSpec.describe 'Tolzar super admin audit', type: :request do
  let!(:super_admin) { create(:super_admin, password: 'Password1!') }

  it 'records a sign-in and a failed one without the password' do
    post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'wrong-Secret9' } }
    post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!' } }
    rows = Tolzar::SuperAdminAudit.recent.limit(2).to_a.reverse
    expect(rows.map(&:action)).to eq(%w[sign_in_failed sign_in])
    expect(rows.last.super_admin_id).to eq(super_admin.id)
    expect(rows.first.super_admin_id).to be_nil
    expect(rows.first.fields).to eq(%w[super_admin.email super_admin.password])
    expect(Tolzar::SuperAdminAudit.where("fields::text LIKE '%wrong-Secret9%'")).to be_empty
  end

  it 'records a change made in the console with the names of the fields only' do
    account = create(:account)
    sign_in(super_admin, scope: :super_admin)
    patch "/super_admin/accounts/#{account.id}", params: { account: { name: 'Renamed Co' } }
    audit = Tolzar::SuperAdminAudit.recent.first
    expect(audit).to have_attributes(controller: 'super_admin/accounts', action: 'update', http_method: 'PATCH',
                                     record_id: account.id.to_s, email: super_admin.email)
    expect(audit.fields).to eq(['account.name'])
    expect(audit.attributes.values.map(&:to_s).join).not_to include('Renamed Co')
  end

  it 'does not record page views, and lists entries on the audit page with search' do
    sign_in(super_admin, scope: :super_admin)
    expect { get '/super_admin/instance_status' }.not_to change(Tolzar::SuperAdminAudit, :count)
    Tolzar::SuperAdminAudit.create!(email: 'someone@tolzar.com', controller: 'super_admin/users', action: 'destroy',
                                    http_method: 'DELETE', path: '/super_admin/users/9', created_at: Time.current)
    get '/super_admin/tolzar_audits', params: { q: 'someone@' }
    expect(response).to have_http_status(:success)
    expect(response.body).to include('someone@tolzar.com', 'users#destroy')
  end

  it 'turns nested params into dotted names' do
    names = Tolzar::SuperAdminAudit.field_names({ 'account' => { 'name' => 'x', 'limits' => { 'agents' => 1 } },
                                                  'authenticity_token' => 't' })
    expect(names).to eq(%w[account.limits.agents account.name])
  end
end

RSpec.describe 'Tolzar super admin audit export', type: :request do
  it 'exports the searched entries as CSV' do
    super_admin = create(:super_admin)
    Tolzar::SuperAdminAudit.create!(email: 'export@tolzar.com', controller: 'super_admin/accounts', action: 'update',
                                    http_method: 'PATCH', path: '/super_admin/accounts/3', fields: ['account.name'], created_at: Time.current)
    sign_in(super_admin, scope: :super_admin)
    get '/super_admin/tolzar_audits/export', params: { q: 'export@' }
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq('text/csv')
    lines = response.body.lines
    expect(lines.first).to start_with('at,email,method')
    expect(lines.last).to include('export@tolzar.com', 'account.name')
  end
end

RSpec.describe 'Tolzar super admin audit filters (c87)', type: :request do
  let(:super_admin) { create(:super_admin) }

  def entry(action, at, note: nil, email: 'ops@tolzar.com')
    Tolzar::SuperAdminAudit.create!(email: email, controller: 'super_admin/x', action: action, http_method: 'POST',
                                    path: "/super_admin/#{action}", fields: [], note: note, created_at: at)
  end

  before { sign_in(super_admin, scope: :super_admin) }

  it 'filters by day and by sign-ins, and exports the note with formulas made text' do
    entry('sign_in', Time.utc(2026, 11, 2, 9))
    entry('sign_in_failed', Time.utc(2026, 11, 2, 10))
    entry('hold', Time.utc(2026, 11, 2, 11), note: '=HYPERLINK("x")')
    entry('update', Time.utc(2026, 10, 1, 9))

    get '/super_admin/tolzar_audits/export', params: { from: '2026-11-01', to: '2026-11-03' }
    rows = CSV.parse(response.body, headers: true)
    expect(rows.pluck('action')).to contain_exactly('sign_in', 'sign_in_failed', 'hold')
    expect(rows.find { |r| r['action'] == 'hold' }['note']).to eq("'=HYPERLINK(\"x\")")

    get '/super_admin/tolzar_audits/export', params: { kind: 'sign_ins' }
    expect(CSV.parse(response.body, headers: true).pluck('action')).to contain_exactly('sign_in', 'sign_in_failed')

    get '/super_admin/tolzar_audits', params: { q: 'HYPERLINK', kind: 'sign_ins' }
    expect(response).to have_http_status(:success)
  end
end
