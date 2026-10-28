# Tolzar: tiny client for the internal brain (internal network only, shared secret header).
#
# Signed account protocol (H1, TOLZAR-SECURITY-FIXES-2026-10-28): every Rails -> brain request
# goes through .sign, which adds
#   X-Tolzar-Brain-Secret  the shared secret (unchanged)
#   X-Tolzar-Account       the account the member was authorised for (0 = no member account:
#                          the public Meta/MCP doors, where the brain checks its own proof)
#   X-Tolzar-Ts            unix seconds
#   X-Tolzar-Body-Sha256   lowercase hex sha256 of the EXACT body bytes sent (of "" when there is none)
#   X-Tolzar-Nonce         a fresh random nonce per request (SecureRandom.hex(16)); the brain accepts
#                          each nonce only once inside the signing window (replay protection)
#   X-Tolzar-Sig           hex(HMAC-SHA256(TOLZAR_BRAIN_SECRET,
#                              "v3\n<account>\n<ts>\n<METHOD>\n<path>\n<body sha256 hex>\n<nonce>"))
# <path> is the request path the brain sees, without the query string. v2 (2026-10-28) also covers
# the body: callers set req.body BEFORE .sign (the hash is of req.body exactly as it is sent).
# v3 (2026-10-28) = v2 + the nonce; .signing_string/.signature still build v2 when given no nonce.
require 'openssl'
require 'digest'
require 'securerandom'

module Tolzar::BrainClient
  module_function

  NO_ACCOUNT = 0

  def get(path, account_id: NO_ACCOUNT)
    request(Net::HTTP::Get.new(uri(path).request_uri), path, account_id)
  end

  def post(path, body, account_id: NO_ACCOUNT)
    req = Net::HTTP::Post.new(uri(path).request_uri, 'Content-Type' => 'application/json')
    req.body = body.to_json
    request(req, path, account_id)
  end

  def base_url
    ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080')
  end

  def uri(path)
    URI.join(base_url, path)
  end

  # The brain's host (for "only to the brain" checks, e.g. the webhook secret header).
  def brain_host
    URI(base_url).host
  rescue URI::InvalidURIError
    nil
  end

  def secret
    ENV['TOLZAR_BRAIN_SECRET'].to_s
  end

  def body_sha256(body)
    Digest::SHA256.hexdigest(body.to_s)
  end

  # The signed string (v3 with a nonce, v2 without) and its HMAC. Pure: the spec pins the brain's
  # own test vectors.
  def signing_string(account_id, ts, method, path, body_hex, nonce = nil)
    base = "#{account_id.to_i}\n#{ts.to_i}\n#{method.to_s.upcase}\n#{path.to_s.split('?', 2).first}\n#{body_hex.to_s.downcase}"
    nonce.nil? ? "v2\n#{base}" : "v3\n#{base}\n#{nonce}"
  end

  def signature(key, account_id, ts, method, path, body_hex, nonce = nil)
    OpenSSL::HMAC.hexdigest('SHA256', key.to_s, signing_string(account_id, ts, method, path, body_hex, nonce))
  end

  # Adds the shared-secret, signed-account, body-hash and nonce headers (v3) to a Net::HTTP request.
  # The one place that signs: every caller of the brain uses it, AFTER setting req.body. Each call
  # gets a fresh nonce (the brain refuses a nonce it has already seen).
  def sign(req, account_id, ts: Time.now.to_i, nonce: SecureRandom.hex(16))
    key = secret
    return req if key.empty?
    raise ArgumentError, 'Tolzar::BrainClient.sign: a body stream cannot be signed' if req.body_stream

    body_hex = body_sha256(req.body)
    req['X-Tolzar-Brain-Secret'] = key
    req['X-Tolzar-Account'] = account_id.to_i.to_s
    req['X-Tolzar-Ts'] = ts.to_i.to_s
    req['X-Tolzar-Body-Sha256'] = body_hex
    req['X-Tolzar-Nonce'] = nonce.to_s
    req['X-Tolzar-Sig'] = signature(key, account_id, ts, req.method, req.path, body_hex, nonce.to_s)
    req
  end

  def request(req, path, account_id)
    u = uri(path)
    http = Net::HTTP.new(u.host, u.port)
    http.read_timeout = 60
    http.open_timeout = 5
    sign(req, account_id)
    res = http.request(req)
    { 'status' => res.code.to_i }.merge(JSON.parse(res.body.presence || '{}'))
  rescue StandardError => e
    Rails.logger.warn("[tolzar-brain] #{path}: #{e.class}")
    { 'status' => 502, 'ok' => false, 'error' => 'brain_unreachable' }
  end
end
