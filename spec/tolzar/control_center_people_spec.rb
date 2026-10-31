require 'rails_helper'

# Tolzar Control Center people actions (typed e-mail + reason, audited with the reason) and the debranded console.
RSpec.describe 'Tolzar Control Center people actions', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:person) { create(:user, account: account, role: :administrator, email: 'mona@example.com') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'refuses without the typed e-mail and a reason' do
    person.update!(tokens: { 'client1' => { 'token' => 'x', 'expiry' => 1.day.from_now.to_i } })
    post "/super_admin/control_center/people/#{person.id}/end_sessions", params: { confirm: 'someone@else.com', reason: 'left the company' }
    expect(response).to redirect_to(super_admin_tolzar_cc_people_path)
    expect(person.reload.tokens).not_to be_empty
    post "/super_admin/control_center/people/#{person.id}/end_sessions", params: { confirm: person.email, reason: '' }
    expect(person.reload.tokens).not_to be_empty
  end

  it 'ends every session and records the reason in the audit log' do
    person.update!(tokens: { 'client1' => { 'token' => 'x', 'expiry' => 1.day.from_now.to_i } })
    expect do
      post "/super_admin/control_center/people/#{person.id}/end_sessions", params: { confirm: 'MONA@example.com', reason: 'lost laptop' }
    end.to change(Tolzar::SuperAdminAudit, :count).by(1)
    expect(person.reload.tokens).to be_empty
    audit = Tolzar::SuperAdminAudit.recent.first
    expect(audit).to have_attributes(action: 'end_sessions', record_id: person.id.to_s, note: 'lost laptop', email: super_admin.email)
  end

  it 'resets two-factor sign-in' do
    skip('MFA is not configured in this environment') unless Chatwoot.encryption_configured?
    person.enable_two_factor!
    person.update!(otp_required_for_login: true)
    post "/super_admin/control_center/people/#{person.id}/reset_two_factor", params: { confirm: person.email, reason: 'new phone, locked out' }
    expect(person.reload.otp_required_for_login).to be(false)
  end

  it 'shows the actions on the people page and no upstream support links in settings' do
    person
    get '/super_admin/control_center/people'
    expect(response.body).to include('Sign out everywhere', 'Reset 2FA')
    get '/super_admin/settings'
    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('discord.gg')
  end
end
