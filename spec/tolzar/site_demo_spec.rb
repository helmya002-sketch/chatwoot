require 'rails_helper'

# The website's live demo door (Tolzar::SiteDemoController): simple CORS posts, per-IP and per-session limits, the
# session's last turns kept 30 minutes, answers from the brain's demo engine (stubbed here).
RSpec.describe 'Tolzar site live demo', type: :request do
  let(:env) { { TOLZAR_CONTACT_ORIGINS: 'https://tolzar.com' } }
  let(:session) { 'sess-1234abcd' }
  let(:brain_answer) do
    { 'status' => 200, 'ok' => true, 'reply' => 'Yes, we deliver to Dubai in 2 to 3 working days.',
      'checks' => { 'price' => 'na', 'offer' => 'pass', 'rules' => 'pass', 'language' => 'pass', 'extra' => 'x' },
      'handoff' => false, 'handoff_reason' => nil, 'why' => ['Delivery and returns'], 'lang' => 'en',
      'business' => { 'name' => 'Nile Bikes (demo)', 'label' => 'Demo business · demo data' } }
  end
  let(:posts) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Redis::Alfred.delete('tolzar:site_demo:ip:127.0.0.1:h')
    Redis::Alfred.delete('tolzar:site_demo:ip:127.0.0.1:d')
    Redis::Alfred.delete("tolzar:site_demo:#{Digest::SHA256.hexdigest(session)}")
    allow(Tolzar::BrainClient).to receive(:post) do |path, body|
      posts << [path, body]
      brain_answer
    end
  end

  def ask(message, **extra)
    post '/tolzar/site/demo', params: { industry: 'ecommerce', message: message, session: session, **extra },
                              headers: { 'Accept' => 'application/json', 'Origin' => 'https://tolzar.com' }
  end

  it 'answers with the reply, the four checks, why, the business label and the turns left' do
    ask('Do you deliver to Dubai?')
    expect(response).to have_http_status(:ok)
    expect(response.headers['Access-Control-Allow-Origin']).to eq('https://tolzar.com')
    body = response.parsed_body
    expect(body['reply']).to include('Dubai')
    expect(body['checks'].keys).to contain_exactly('price', 'offer', 'rules', 'language')
    expect(body['business']['label']).to eq('Demo business · demo data')
    expect(body['turns_left']).to eq(5)
    expect(posts.last).to eq(['/demo/answer', { industry: 'ecommerce',
                                                messages: [{ 'role' => 'visitor', 'text' => 'Do you deliver to Dubai?' }] }])
  end

  it 'sends the session history back to the brain on the next turn' do
    ask('Do you deliver to Dubai?')
    ask('How much is delivery?')
    roles = posts.last[1][:messages].pluck('role')
    expect(roles).to eq(%w[visitor ai visitor])
  end

  it 'stops a session after six questions' do
    6.times { |i| ask("Question #{i}") }
    ask('One more')
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body['error']).to eq('rate')
  end

  it 'refuses bad input without calling the brain' do
    ask('x' * 301)
    expect(response).to have_http_status(:bad_request)
    post '/tolzar/site/demo', params: { industry: 'ecommerce', message: 'hi', session: 'bad id!' }
    expect(response).to have_http_status(:bad_request)
    expect(posts).to be_empty
  end

  it 'passes the brain\'s busy and unknown-industry answers on' do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 503 })
    ask('Hello?')
    expect(response).to have_http_status(:service_unavailable)
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 404 })
    ask('Hello again?')
    expect(response.parsed_body['error']).to eq('industry_unavailable')
  end

  it 'lists the demo businesses, and 404s while the brain has the demo off' do
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 200, 'businesses' => [{ 'industry' => 'ecommerce' }] })
    get '/tolzar/site/demo/businesses'
    expect(response.parsed_body['businesses'].first['industry']).to eq('ecommerce')
    allow(Tolzar::BrainClient).to receive(:get).and_return({ 'status' => 404 })
    get '/tolzar/site/demo/businesses'
    expect(response).to have_http_status(:not_found)
  end
end
