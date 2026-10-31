require 'rails_helper'

# Tolzar account e-mails (round 4, c83): with TOLZAR_NEW_EMAILS=true the password-reset, password-changed and unlock
# mails use the confirmation mail's card (heading, short copy, Tolzar button, fallback link); otherwise they are
# exactly as before. The links and tokens are the same either way.
RSpec.describe 'Tolzar account e-mails' do
  let(:user) { create(:user, name: 'Mona Adel') }

  def html(mail)
    (mail.html_part || mail).body.decoded
  end

  it 'keeps the old reset mail while the switch is off' do
    body = html(Devise::Mailer.reset_password_instructions(user, 'tok123'))
    expect(body).to include('Someone has requested a link', 'tok123')
    expect(body).not_to include('Choose a new password')
  end

  it 'uses the card with the same link when the switch is on' do
    with_modified_env(TOLZAR_NEW_EMAILS: 'true') do
      reset = html(Devise::Mailer.reset_password_instructions(user, 'tok123'))
      expect(reset).to include('Choose a new password', 'Hi Mona Adel', 'Change my password', 'reset_password_token=tok123')

      changed = html(Devise::Mailer.password_change(user))
      expect(changed).to include('Your password was changed')
      expect(changed).not_to include('this secure link') # no button: nothing to click

      unlock = html(Devise::Mailer.unlock_instructions(user, 'unl456'))
      expect(unlock).to include('Your account was locked', 'Unlock my account', 'unlock_token=unl456')
    end
  end
end
