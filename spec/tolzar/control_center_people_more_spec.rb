require 'rails_helper'

# Tolzar Control Center people, part 2 (round 4, c86): deactivate / reactivate a person (typed e-mail + reason,
# audited; a deactivated person cannot sign in or use an API token; nothing deleted), and invite a person to a
# workspace (typed workspace name + reason, agent or administrator only, Chatwoot's own invitation, audited).
RSpec.describe 'Tolzar Control Center people, part 2', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Nile Boats') }
  let(:person) { create(:user, account: account, email: 'mona@tolzar.com') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'deactivates only with the typed e-mail and a reason, blocks sign-in and tokens, and reactivates' do
    token_headers = person.create_new_auth_token
    post "/super_admin/control_center/people/#{person.id}/deactivate", params: { confirm: 'mona', reason: 'left the company' }
    expect(person.reload.tolzar_deactivated_at).to be_nil

    post "/super_admin/control_center/people/#{person.id}/deactivate", params: { confirm: 'mona@tolzar.com', reason: 'left the company' }
    expect(person.reload.tolzar_deactivated_at).to be_present
    expect(person.active_for_authentication?).to be(false)
    expect(Tolzar::SuperAdminAudit.recent.first).to have_attributes(action: 'deactivate', note: 'left the company')
    get "/api/v1/accounts/#{account.id}/conversations", headers: token_headers
    expect(response).to have_http_status(:unauthorized)

    post "/super_admin/control_center/people/#{person.id}/reactivate", params: { confirm: 'mona@tolzar.com', reason: 'came back' }
    expect(person.reload.tolzar_deactivated_at).to be_nil
    expect(person.active_for_authentication?).to be(true)
  end

  it 'invites a person to a workspace only with the typed workspace name, a reason and a plain role' do
    post '/super_admin/control_center/people/invite',
         params: { account_id: account.id, email: 'omar@tolzar.com', role: 'administrator', confirm: 'Nile', reason: 'new manager' }
    expect(User.find_by(email: 'omar@tolzar.com')).to be_nil

    post '/super_admin/control_center/people/invite',
         params: { account_id: account.id, email: 'omar@tolzar.com', role: 'owner', confirm: 'Nile Boats', reason: 'new manager' }
    expect(User.find_by(email: 'omar@tolzar.com')).to be_nil

    post '/super_admin/control_center/people/invite',
         params: { account_id: account.id, email: 'Omar@Tolzar.com', role: 'administrator', confirm: 'Nile Boats', reason: 'new manager' }
    omar = User.find_by(email: 'omar@tolzar.com')
    expect(omar.account_users.find_by(account: account)).to be_administrator
    expect(Tolzar::SuperAdminAudit.recent.first).to have_attributes(action: 'invite', record_id: omar.id.to_s)
  end
end
