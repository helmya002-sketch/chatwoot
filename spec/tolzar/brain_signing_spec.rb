require 'rails_helper'

# H1 + v2 (TOLZAR-SECURITY-FIXES-2026-10-28): every Rails -> brain request carries the signed
# account AND the hash of the exact body it sends.
#   X-Tolzar-Body-Sha256 = hex(sha256(body bytes as sent))            ("" when there is no body)
#   X-Tolzar-Sig = hex(HMAC-SHA256(TOLZAR_BRAIN_SECRET,
#                  "v2\n<account>\n<ts>\n<METHOD>\n<path without query>\n<body sha256 hex>"))
# The vectors below are the brain's own (brain/tests/test_n_lang_fixes.py test_v2_test_vector,
# and tolzar_brain.auth.sign for the body vector).
RSpec.describe 'Tolzar signed account protocol (H1, v2 body signing)' do
  let(:secret) { 'tolzar-test-secret-0123456789abcdef' }
  let(:brain) { 'http://tolzar-brain:8080' }
  let(:empty_sha) { 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }

  around { |example| with_modified_env(TOLZAR_BRAIN_SECRET: secret, TOLZAR_BRAIN_URL: brain) { example.run } }

  def expected_sig(account_id, ts, method, path, body)
    OpenSSL::HMAC.hexdigest('SHA256', secret,
                            "v2\n#{account_id}\n#{ts}\n#{method}\n#{path}\n#{Digest::SHA256.hexdigest(body.to_s)}")
  end

  describe Tolzar::BrainClient do
    it 'signs exactly the brain v2 test vectors' do
      brain_secret = 's' * 32
      expect(described_class.body_sha256(nil)).to eq(empty_sha)
      expect(described_class.body_sha256('')).to eq(empty_sha)
      expect(described_class.signing_string(7, 1_700_000_000, 'post', '/agents?x=1', empty_sha))
        .to eq("v2\n7\n1700000000\nPOST\n/agents\n#{empty_sha}")
      expect(described_class.signature(brain_secret, 7, 1_700_000_000, 'POST', '/agents?x=1', empty_sha))
        .to eq('66b6c85b542cf6ac3bbd2f08faedb71c5de616a60a9ac83f6aacaffee31d44ca')
      body = '{"code":"c0de","state":"5.p.s"}'
      body_hex = described_class.body_sha256(body)
      expect(body_hex).to eq('9c1c3bc5e8a5a8a8ae60f2e7147be8ec0d99874bbb0aca32577e48e7de76387a')
      expect(described_class.signature(brain_secret, 0, 1_700_000_000, 'POST', '/meta/callback', body_hex))
        .to eq('4eda2805f3eab0b8c646317ffda72d0d58f7f87737f9df32b9de731f68e78dd5')
    end

    it 'adds the five headers to a request, hashing the body set before signing' do
      req = Net::HTTP::Post.new('/agents?x=1')
      req.body = '{"a":1}'
      described_class.sign(req, 7, ts: 1_700_000_000)
      expect(req['X-Tolzar-Brain-Secret']).to eq(secret)
      expect(req['X-Tolzar-Account']).to eq('7')
      expect(req['X-Tolzar-Ts']).to eq('1700000000')
      expect(req['X-Tolzar-Body-Sha256']).to eq(Digest::SHA256.hexdigest('{"a":1}'))
      expect(req['X-Tolzar-Sig']).to eq(expected_sig(7, 1_700_000_000, 'POST', '/agents', '{"a":1}'))

      get = Net::HTTP::Get.new('/workflows/runs?account_id=7&limit=100')
      described_class.sign(get, 7, ts: 1_700_000_000)
      expect(get['X-Tolzar-Body-Sha256']).to eq(empty_sha)
      expect(get['X-Tolzar-Sig']).to eq(expected_sig(7, 1_700_000_000, 'GET', '/workflows/runs', ''))
    end

    it 'signs a real POST: the hash header is of the bytes that went over the wire' do
      seen = {}
      stub_request(:post, "#{brain}/documents").with { |req| seen[:headers] = req.headers; seen[:body] = req.body }
                                               .to_return(body: '{"ok":true}')
      expect(described_class.post('/documents', { account_id: 3, text: "café" }, account_id: 3)).to include('ok' => true)
      h = seen[:headers]
      expect(h['X-Tolzar-Body-Sha256']).to eq(Digest::SHA256.hexdigest(seen[:body]))
      expect(h['X-Tolzar-Sig']).to eq(expected_sig(3, h['X-Tolzar-Ts'], 'POST', '/documents', seen[:body]))
    end

    it 'signs the export job call for the job account (GET, empty body hash)' do
      stub = stub_request(:get, "#{brain}/export?account_id=42").with do |req|
        ts = req.headers['X-Tolzar-Ts']
        req.headers['X-Tolzar-Account'] == '42' && req.headers['X-Tolzar-Body-Sha256'] == empty_sha &&
          req.headers['X-Tolzar-Sig'] == expected_sig(42, ts, 'GET', '/export', '')
      end.to_return(body: '{"ok":true}')
      expect(described_class.get('/export?account_id=42', account_id: 42)).to include('ok' => true)
      expect(stub).to have_been_requested
    end
  end

  describe 'the admin proxy', type: :request do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'signs a GET for the URL account (path without the query, empty body)' do
      seen = nil
      stub_request(:get, %r{\A#{brain}/workflows\?}).with { |req| seen = req.headers }.to_return(body: '{"ok":true}')
      get "/api/v1/accounts/#{account.id}/tolzar/workflows", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(seen['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(seen['X-Tolzar-Body-Sha256']).to eq(empty_sha)
      expect(seen['X-Tolzar-Sig']).to eq(expected_sig(account.id, seen['X-Tolzar-Ts'], 'GET', '/workflows', ''))
    end

    it 'signs a POST and its exact body for the URL account even when the body names another account' do
      seen = {}
      stub_request(:post, "#{brain}/documents").with { |req| seen[:headers] = req.headers; seen[:body] = req.body }
                                               .to_return(body: '{"ok":true}')
      post "/api/v1/accounts/#{account.id}/tolzar/brain/documents", params: { mode: 'shadow', account_id: other_account.id },
                                                                    headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      h = seen[:headers]
      expect(h['X-Tolzar-Account']).to eq(account.id.to_s)
      expect(seen[:body]).to be_present
      expect(h['X-Tolzar-Body-Sha256']).to eq(Digest::SHA256.hexdigest(seen[:body]))
      expect(h['X-Tolzar-Sig']).to eq(expected_sig(account.id, h['X-Tolzar-Ts'], 'POST', '/documents', seen[:body]))
    end
  end
end
