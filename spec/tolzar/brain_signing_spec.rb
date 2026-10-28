require 'rails_helper'

# H1 (TOLZAR-SECURITY-FIXES-2026-10-28): every Rails -> brain request carries the signed account.
#   X-Tolzar-Sig = hex(HMAC-SHA256(TOLZAR_BRAIN_SECRET, "v1\n<account>\n<ts>\n<METHOD>\n<path without query>"))
# The test vectors below are the ones the brain's verifier is cross-checked against.
RSpec.describe 'Tolzar signed account protocol (H1)' do
  let(:secret) { 'tolzar-test-secret-0123456789abcdef' }
  let(:brain) { 'http://tolzar-brain:8080' }

  around { |example| with_modified_env(TOLZAR_BRAIN_SECRET: secret, TOLZAR_BRAIN_URL: brain) { example.run } }

  def expected_sig(account_id, ts, method, path)
    OpenSSL::HMAC.hexdigest('SHA256', secret, "v1\n#{account_id}\n#{ts}\n#{method}\n#{path}")
  end

  describe Tolzar::BrainClient do
    it 'signs the exact string of the protocol (fixed test vectors)' do
      expect(described_class.signing_string(7, 1_700_000_000, 'post', '/agents?x=1')).to eq("v1\n7\n1700000000\nPOST\n/agents")
      expect(described_class.signature(secret, 7, 1_700_000_000, 'POST', '/agents'))
        .to eq('15eb5a96efe666cfa6d6e4fb9addd285c8f36b117a051e252901b98ab7571335')
      expect(described_class.signature(secret, 7, 1_700_000_000, 'GET', '/workflows/runs?account_id=7&limit=100'))
        .to eq('e14cf9be52c7cc405bd1b9a835a5490577fd31044206af182bf65feaa75029e8')
      expect(described_class.signature(secret, 0, 1_700_000_000, 'POST', '/meta/callback'))
        .to eq('58b497f70d1fb695c47ae0686a0be1d5fd3fa6ef26439fdb17d63ee2a7b29bfc')
      # The MCP door (route only drawn with TOLZAR_MCP_PUBLIC=true) signs POST /mcp/ for account 0.
      expect(described_class.signature(secret, 0, 1_700_000_000, 'POST', '/mcp/'))
        .to eq('a9ab6980d52e4b1447d6272f7b44ea816697f1be652d50343a64bb3db2f92b1f')
    end

    it 'adds the four headers to a request' do
      req = Net::HTTP::Get.new('/workflows/runs?account_id=7&limit=100')
      described_class.sign(req, 7, ts: 1_700_000_000)
      expect(req['X-Tolzar-Brain-Secret']).to eq(secret)
      expect(req['X-Tolzar-Account']).to eq('7')
      expect(req['X-Tolzar-Ts']).to eq('1700000000')
      expect(req['X-Tolzar-Sig']).to eq('e14cf9be52c7cc405bd1b9a835a5490577fd31044206af182bf65feaa75029e8')
    end

    it 'signs the export job call for the job account' do
      stub = stub_request(:get, "#{brain}/export?account_id=42").with do |req|
        ts = req.headers['X-Tolzar-Ts']
        req.headers['X-Tolzar-Account'] == '42' && req.headers['X-Tolzar-Sig'] == expected_sig(42, ts, 'GET', '/export')
      end.to_return(body: '{"ok":true}')
      expect(described_class.get('/export?account_id=42', account_id: 42)).to include('ok' => true)
      expect(stub).to have_been_requested
    end
  end

  describe 'the admin proxy', type: :request do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'signs a GET for the URL account (path without the query)' do
      seen = nil
      stub_request(:get, %r{\A#{brain}/workflows\?}).with { |req| seen = req.headers }.to_return(body: '{"ok":true}')
      get "/api/v1/accounts/#{account.id}/tolzar/workflows", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(seen['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(seen['X-Tolzar-Sig']).to eq(expected_sig(account.id, seen['X-Tolzar-Ts'], 'GET', '/workflows'))
    end

    it 'signs a POST for the URL account even when the body names another account' do
      seen = nil
      stub_request(:post, "#{brain}/documents").with { |req| seen = req.headers }.to_return(body: '{"ok":true}')
      post "/api/v1/accounts/#{account.id}/tolzar/brain/documents", params: { mode: 'shadow', account_id: other_account.id },
                                                                    headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(seen['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(seen['X-Tolzar-Sig']).to eq(expected_sig(account.id, seen['X-Tolzar-Ts'], 'POST', '/documents'))
    end
  end
end
