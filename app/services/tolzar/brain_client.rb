# Tolzar: tiny client for the internal brain (internal network only, shared secret header).
module Tolzar::BrainClient
  module_function

  def get(path)
    request(Net::HTTP::Get.new(uri(path).request_uri), path)
  end

  def post(path, body)
    req = Net::HTTP::Post.new(uri(path).request_uri, 'Content-Type' => 'application/json')
    req.body = body.to_json
    request(req, path)
  end

  def uri(path)
    URI.join(ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080'), path)
  end

  def request(req, path)
    u = uri(path)
    http = Net::HTTP.new(u.host, u.port)
    http.read_timeout = 60
    http.open_timeout = 5
    secret = ENV['TOLZAR_BRAIN_SECRET'].to_s
    req['X-Tolzar-Brain-Secret'] = secret unless secret.empty?
    res = http.request(req)
    { 'status' => res.code.to_i }.merge(JSON.parse(res.body.presence || '{}'))
  rescue StandardError => e
    Rails.logger.warn("[tolzar-brain] #{path}: #{e.class}")
    { 'status' => 502, 'ok' => false, 'error' => 'brain_unreachable' }
  end
end
