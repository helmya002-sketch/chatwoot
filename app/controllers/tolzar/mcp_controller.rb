# Tolzar MCP server (roadmap F1), public door: forwards the MCP JSON-RPC request to the brain's
# read-only MCP endpoint with the caller's Authorization header. The brain checks the workspace
# token (only its hash is stored) and only ever answers with that workspace's data.
class Tolzar::McpController < ActionController::API
  def forward
    uri = URI.join(ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080'), '/mcp/')
    klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }[request.method]
    req = klass.new(uri.request_uri)
    %w[Authorization Accept Content-Type Mcp-Session-Id Mcp-Protocol-Version].each do |h|
      req[h] = request.headers[h] if request.headers[h].present?
    end
    req.body = request.raw_post if request.post?
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120
    res = http.request(req)
    render body: res.body, status: res.code.to_i, content_type: res['Content-Type'] || 'application/json'
  rescue StandardError => e
    Rails.logger.warn("[tolzar-mcp] #{e.class}")
    render json: { error: 'brain_unreachable' }, status: :bad_gateway
  end
end
