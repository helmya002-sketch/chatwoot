require 'rails_helper'

# Readiness ranking #4: the widget snippet customers copy uses TOLZAR_WIDGET_BASE_URL (never the operator's
# FRONTEND_URL when it is set); channel webhooks stay on FRONTEND_URL.
RSpec.describe Tolzar::PublicUrls do
  let(:widget) { create(:channel_widget) }

  it 'builds the snippet on TOLZAR_WIDGET_BASE_URL when set, else on FRONTEND_URL' do
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TOLZAR_WIDGET_BASE_URL: 'https://app.example.com/') do
      expect(described_class.widget_base).to eq('https://app.example.com')
      expect(widget.web_widget_script).to include('BASE_URL="https://app.example.com"')
      expect(widget.web_widget_script).not_to include('chat.example.com')
    end
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TOLZAR_WIDGET_BASE_URL: '') do
      expect(widget.web_widget_script).to include('BASE_URL="https://chat.example.com"')
    end
  end

  it 'leaves channel webhook URLs on FRONTEND_URL' do
    with_modified_env(FRONTEND_URL: 'https://chat.example.com', TOLZAR_WIDGET_BASE_URL: 'https://app.example.com') do
      sms = build(:channel_sms, phone_number: '+15550001111')
      expect(sms.webhook_url).to start_with('https://chat.example.com/')
    end
  end
end
