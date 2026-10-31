require 'rails_helper'

# In-app open-source notices (launch lane, 31 Oct): the licence compliance moved from the marketing site into
# the product. Every signed-in member of the workspace reads them; nobody else does.
RSpec.describe 'Tolzar open-source licences', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:stranger) { create(:user) }

  before { Tolzar::OpenSourceNotices.reset! }
  after { Tolzar::OpenSourceNotices.reset! }

  describe Tolzar::OpenSourceNotices do
    subject(:notices) { described_class.call }

    it 'starts with the inbox foundation\'s MIT notice' do
      expect(notices[:foundation][:licences]).to eq(['MIT'])
      expect(notices[:foundation][:text]).to include('Permission is hereby granted')
    end

    it 'lists every loaded gem with its version, licences and shipped licence text' do
      rails = notices[:groups][:gems].find { |g| g[:name] == 'rails' }
      expect(rails).to include(version: Rails.version, licences: ['MIT'])
      expect(notices[:groups][:gems].size).to eq(Bundler.load.specs.size)
      expect(notices[:groups][:gems].pluck(:text)).to include(a_string_including('Permission is hereby granted'))
    end

    it 'lists the AI service: the brain packages from the committed file, its runtime and the model' do
      names = notices[:groups][:ai].pluck(:name)
      expect(names).to include('fastapi', 'Ollama', 'Qwen2.5-7B-Instruct (model weights)')
      expect(notices[:groups][:system].pluck(:name)).to include('Ruby', 'libvips')
    end

    it 'puts weak-copyleft components in the source offer with where their source is' do
      vips = notices[:source_offer].find { |i| i[:name] == 'libvips' }
      expect(vips).to include(licences: ['LGPL-2.1-or-later'], homepage: Tolzar::OpenSourceNotices::VIPS_SOURCE)
      expect(notices[:source_offer]).to all(satisfy { |i| i[:licences].join(' ').match?(described_class::WEAK_COPYLEFT) })
    end

    it 'reads the JavaScript notices written at image build, and copes when they are missing' do
      file = Rails.root.join('tmp/js_notices_spec.json')
      File.write(file, { items: [{ name: 'vue', version: '3.5.0', licences: ['MIT'], text: 'MIT vue' }] }.to_json)
      stub_const('Tolzar::OpenSourceNotices::JS_FILE', file)
      expect(described_class.new.call[:groups][:javascript]).to contain_exactly(include(name: 'vue', text: 'MIT vue'))
      File.write(file, 'not json')
      expect(described_class.new.call[:groups][:javascript]).to eq([])
      stub_const('Tolzar::OpenSourceNotices::JS_FILE', Rails.root.join('tmp/absent.json'))
      expect(described_class.new.call[:groups][:javascript]).to eq([])
    ensure
      FileUtils.rm_f(file)
    end

    it 'reads the image\'s Alpine packages when the apk database exists' do
      db = Rails.root.join('tmp/apk_installed_spec')
      File.write(db, <<~APK)
        P:musl
        V:1.2.5-r1
        L:MIT
        U:https://musl.libc.org/

        P:gmp
        V:6.3.0-r2
        L:LGPL-3.0-or-later OR GPL-2.0-or-later
        U:https://gmplib.org/
      APK
      stub_const('Tolzar::OpenSourceNotices::APK_DB', db.to_s)
      out = described_class.new.call
      expect(out[:groups][:system]).to include(include(name: 'musl', version: '1.2.5-r1', licences: ['MIT']))
      expect(out[:source_offer].pluck(:name)).to include('gmp')
    ensure
      FileUtils.rm_f(db)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/open_source_licences' do
    it 'answers any signed-in member of the workspace' do
      get "/api/v1/accounts/#{account.id}/open_source_licences", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['foundation']['licences']).to eq(['MIT'])
      expect(body['groups'].keys).to contain_exactly('gems', 'javascript', 'system', 'ai')
      expect(body['counts']['gems']).to be > 0
    end

    it 'refuses a visitor and a user of another workspace' do
      get "/api/v1/accounts/#{account.id}/open_source_licences", as: :json
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/accounts/#{account.id}/open_source_licences", headers: stranger.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
