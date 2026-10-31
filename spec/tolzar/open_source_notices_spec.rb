require 'rails_helper'

# In-app open-source notices (launch lane, 31 Oct): the licence compliance moved from the marketing site into
# the product. Every signed-in member of the workspace reads them; nobody else does.
RSpec.describe 'Tolzar open-source licences', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:stranger) { create(:user) }

  before do
    Tolzar::OpenSourceNotices.reset!
    allow(Tolzar::BrainClient).to receive(:get).and_return('status' => 502)   # no brain in specs
  end
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
      # Bundler's spec set differs between calls in a full suite run (other specs load more groups), so check
      # the gems the app needs at run time rather than an exact count (c12 gate, 31 Oct: 382 vs 417).
      names = notices[:groups][:gems].pluck(:name)
      expect(names).to include('rails', 'sidekiq', 'pg', 'ruby-vips')
      expect(names.size).to be > 100
      expect(notices[:groups][:gems].pluck(:text)).to include(a_string_including('Permission is hereby granted'))
    end

    it 'lists the AI service: the brain packages, its runtime and the model the running brain answers with' do
      allow(Tolzar::BrainClient).to receive(:get).with('/notices/ai', account_id: 5).and_return(
        'status' => 200, 'items' => [
          { 'name' => 'Gemma 4 E4B', 'version' => 'gemma-4-e4b', 'licences' => ['Apache-2.0'], 'role' => 'production' },
          { 'name' => 'Qwen2.5-7B-Instruct', 'version' => 'qwen2.5:7b-instruct', 'licences' => ['Apache-2.0'], 'role' => 'rollback' }
        ]
      )
      ai = described_class.call(5)[:groups][:ai]
      expect(ai.pluck(:name)).to include('fastapi', 'Python', 'Gemma 4 E4B', 'Qwen2.5-7B-Instruct')
      expect(ai.find { |i| i[:name] == 'Qwen2.5-7B-Instruct' }[:role]).to eq('rollback')
      expect(described_class.call(5)[:counts][:ai]).to eq(ai.size)
      expect(notices[:groups][:system].pluck(:name)).to include('Ruby', 'libvips')
    end

    it 'says the model list is unavailable when the brain does not answer, and asks again next time' do
      allow(Tolzar::BrainClient).to receive(:get).and_return('status' => 502)
      expect(described_class.call(5)[:groups][:ai].last[:name]).to start_with('AI model (the list is unavailable')
      allow(Tolzar::BrainClient).to receive(:get).and_return('status' => 200, 'items' => [{ 'name' => 'Gemma 4 E4B' }])
      expect(described_class.call(5)[:groups][:ai].pluck(:name)).to include('Gemma 4 E4B')
    end

    it 'puts weak-copyleft components in the source offer with where their source is' do
      vips = notices[:source_offer].find { |i| i[:name] == 'libvips' }
      expect(vips).to include(licences: ['LGPL-2.1-or-later'], homepage: Tolzar::OpenSourceNotices::VIPS_SOURCE)
      expect(notices[:source_offer]).to all(satisfy { |i| i[:licences].join(' ').match?(described_class::WEAK_COPYLEFT) })
    end

    it 'lists the PDF renderer stack, with Pyphen and Pango in the source offer' do
      ai_names = notices[:groups][:ai].pluck(:name)
      expect(ai_names).to include('weasyprint', 'pyphen', 'Pango, Cairo, GLib (brain image, PDF text layout)')
      offer = notices[:source_offer].pluck(:name)
      expect(offer).to include('pyphen', 'Pango, Cairo, GLib (brain image, PDF text layout)')
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
