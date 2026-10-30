require 'rails_helper'

# Hardening (Oracle, item J): one env list for the Host allow-list and ActionCable's request origins.
RSpec.describe TolzarAllowedHosts do
  it 'is off when TOLZAR_ALLOWED_HOSTS is empty' do
    with_modified_env(TOLZAR_ALLOWED_HOSTS: '') do
      expect(described_class.enabled?).to be(false)
    end
  end

  it 'reads the hosts and allows only their browser origins on the cable' do
    with_modified_env(TOLZAR_ALLOWED_HOSTS: ' chat.example.com, App.Tolzar.example ,localhost') do
      expect(described_class.hosts).to eq(%w[chat.example.com app.tolzar.example localhost])
      expect(described_class.cable_origin_allowed?('https://app.tolzar.example')).to be(true)
      expect(described_class.cable_origin_allowed?('https://chat.example.com:443')).to be(true)
      expect(described_class.cable_origin_allowed?('https://evil.example')).to be(false)
      expect(described_class.cable_origin_allowed?('https://chat.example.com.evil.example')).to be(false)
      expect(described_class.cable_origin_allowed?(nil)).to be(true) # native apps send no Origin
      expect(described_class.cable_origin_allowed?('not a url ::')).to be(false)
    end
  end
end
