# Tolzar MCP server (roadmap F1), public door: forwards the MCP JSON-RPC request to the brain's
# read-only MCP endpoint with the caller's Authorization header. The brain checks the workspace
# token (only its hash is stored) and only ever answers with that workspace's data.
# Signed (H1) with no member account (0): the workspace comes from the token, which the brain checks.
class Tolzar::McpController < ActionController::API
  def forward
    uri = Tolzar::BrainClient.uri('/mcp/')
    klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }[request.method]
    req = klass.new(uri.request_uri)
    %w[Authorization Accept Content-Type Mcp-Session-Id Mcp-Protocol-Version].each do |h|
      req[h] = request.headers[h] if request.headers[h].present?
    end
    # The brain rate-limits and locks out per client address: pass the real one (set, not appended).
    req['X-Forwarded-For'] = request.remote_ip.to_s
    req.body = request.raw_post if request.post?
    Tolzar::BrainClient.sign(req, Tolzar::BrainClient::NO_ACCOUNT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120
    res = http.request(req)
    render body: res.body, status: res.code.to_i, content_type: res['Content-Type'] || 'application/json'
  rescue StandardError => e
    Rails.logger.warn("[tolzar-mcp] #{e.class}")
    render json: { error: 'brain_unreachable' }, status: :bad_gateway
  end
end
