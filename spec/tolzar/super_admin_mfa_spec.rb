require 'rails_helper'

# Tolzar Control Center: the super admins' two-factor sign-in behind TOLZAR_SUPERADMIN_2FA_REQUIRED, its lock-out
# guard (no effect while any super admin lacks 2FA), and the read-only Switches & 2FA page.
RSpec.describe 'Tolzar super admin 2FA and switches', type: :request do
  let!(:super_admin) { create(:super_admin, password: 'Password1!') }

  def sign_in_with(code = nil)
    post '/super_admin/sign_in',
         params: { super_admin: { email: super_admin.email, password: 'Password1!', otp_code: code }.compact }
  end

  describe 'sign-in' do
    it 'stays password-only while the switch is off' do
      sign_in_with
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'does not take effect while a super admin has no 2FA (lock-out guard)' do
      with_modified_env(TOLZAR_SUPERADMIN_2FA_REQUIRED: 'true') do
        expect(Tolzar::SuperAdminMfa.missing).to include(super_admin.email)
        expect(Tolzar::SuperAdminMfa.enforced?).to be(false)
        sign_in_with
        expect(response).to redirect_to(super_admin_root_path)
      end
    end

    context 'when every super admin has 2FA' do
      before do
        skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
        SuperAdmin.where.not(id: super_admin.id).find_each do |other|
          other.enable_two_factor!
          other.update!(otp_required_for_login: true)
        end
        super_admin.enable_two_factor!
        super_admin.update!(otp_required_for_login: true)
      end

      it 'asks for the one-time code and refuses a wrong or missing one' do
        with_modified_env(TOLZAR_SUPERADMIN_2FA_REQUIRED: 'true') do
          expect(Tolzar::SuperAdminMfa.enforced?).to be(true)
          get '/super_admin/sign_in'
          expect(response.body).to include('super_admin[otp_code]')
          sign_in_with
          expect(response).to redirect_to(super_admin_session_path)
          sign_in_with('000000')
          expect(response).to redirect_to(super_admin_session_path)
          sign_in_with(super_admin.reload.current_otp)
          expect(response).to redirect_to(super_admin_root_path)
        end
      end
    end
  end

  describe 'GET /super_admin/tolzar_switches' do
    let(:env) do
      { TOLZAR_NEW_UI_ACCOUNTS: '5, 7', TOLZAR_BRAIN_SECRET: 'never-shown', TOLZAR_META_WEBHOOK_BASE: 'https://chat.example.com',
        TOLZAR_TRIAL_MAIL_FROM: 'Adam <noreply@example.com>' }
    end

    before do
      allow(Tolzar::BrainClient).to receive(:get).with('/switches').and_return(
        { 'status' => 200, 'switches' => [{ 'name' => 'TOLZAR_DEMO', 'value' => 'on' },
                                          { 'name' => 'TOLZAR_SMTP_PASSWORD', 'value' => 'hunter2' }] }
      )
    end

    it 'redirects without a super admin session' do
      get '/super_admin/tolzar_switches'
      expect(response).to have_http_status(:redirect)
    end

    it 'lists switches with plain values only and never a secret, and who lacks 2FA' do
      with_modified_env(env) do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/tolzar_switches'
        expect(response).to have_http_status(:success)
        body = response.body
        expect(body).to include('TOLZAR_NEW_UI_ACCOUNTS', '5, 7', 'https://chat.example.com', 'TOLZAR_DEMO')
        expect(body).not_to include('never-shown')
        expect(body).not_to include('hunter2')
        expect(body).not_to include('noreply@example.com')
        expect(body).to include(super_admin.email)
      end
    end
  end
end
