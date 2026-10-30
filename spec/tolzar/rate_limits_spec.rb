require 'rails_helper'

# Readiness gap 11: per-IP limits on the public Tolzar POST routes and per-workspace caps on the widget, so a
# flood (even from many addresses) cannot use up a workspace's AI allowance. Meta's webhook is never throttled.
RSpec.describe 'Tolzar rate limits', type: :request do
  around do |example|
    store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = store
  end

  it 'limits each IP on the public contact form (30 a minute by default)' do
    Rack::Attack.reset!
    30.times { post '/tolzar/site/contact', params: { email: 'a@b.co' }, headers: { 'REMOTE_ADDR' => '1.2.3.4' } }
    expect(response).not_to have_http_status(:too_many_requests)
    post '/tolzar/site/contact', params: { email: 'a@b.co' }, headers: { 'REMOTE_ADDR' => '1.2.3.4' }
    expect(response).to have_http_status(:too_many_requests)
    post '/tolzar/site/contact', params: { email: 'a@b.co' }, headers: { 'REMOTE_ADDR' => '5.6.7.8' }
    expect(response).not_to have_http_status(:too_many_requests)
  end

  it 'never throttles the Meta webhook path' do
    throttle = Rack::Attack.throttles['tolzar/public/ip']
    req = Rack::Attack::Request.new(Rack::MockRequest.env_for('/tolzar/meta/hook/abc', method: 'POST', 'REMOTE_ADDR' => '1.2.3.4'))
    expect(throttle.block.call(req)).to be_nil
  end

  it 'keys the widget workspace caps on the website token, whatever the IP' do
    throttle = Rack::Attack.throttles['tolzar/widget/conversations/workspace']
    env = Rack::MockRequest.env_for('/api/v1/widget/conversations?website_token=tok1', method: 'POST', 'REMOTE_ADDR' => '9.9.9.9')
    expect(throttle.block.call(Rack::Attack::Request.new(env))).to eq('tok1')
    other_ip = Rack::MockRequest.env_for('/api/v1/widget/conversations?website_token=tok1', method: 'POST', 'REMOTE_ADDR' => '8.8.8.8')
    expect(throttle.block.call(Rack::Attack::Request.new(other_ip))).to eq('tok1')
  end
end
