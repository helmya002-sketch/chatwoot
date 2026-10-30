require 'rails_helper'

# Queue item J: app.tolzar.com is a second hostname of the same app; mail links use it (TOLZAR_MAIL_LINK_URL)
# while FRONTEND_URL stays chat.xplorer-redsea.com until the DWT App Review is approved.
RSpec.describe AdministratorNotifications::BaseMailer do
  it 'builds mail links on TOLZAR_MAIL_LINK_URL when set, else on FRONTEND_URL' do
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TOLZAR_MAIL_LINK_URL: 'https://app.example.com/') do
      expect(described_class.new.send(:mail_link_base)).to eq('https://app.example.com')
    end
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TOLZAR_MAIL_LINK_URL: '') do
      expect(described_class.new.send(:mail_link_base)).to eq('https://chat.example.com')
    end
  end
end
