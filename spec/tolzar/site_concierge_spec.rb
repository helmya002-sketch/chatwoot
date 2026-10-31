require 'rails_helper'

# The website concierge door (Tolzar::SiteConciergeController): answers from the brain's concierge (stubbed here),
# the action allowlist checked again in Rails, the session's turns, and a hand-off that becomes one conversation in
# Tolzar's own contact inbox.
RSpec.describe 'Tolzar site concierge', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:env) { { TOLZAR_CONTACT_ORIGINS: 'https://tolzar.com', TOLZAR_CONTACT_INBOX_ID: inbox.id.to_s } }
  let(:session) { 'sess-concierge-1' }
  let(:actions) do
    [{ 'type' => 'set_industry', 'slug' => 'clinics' }, { 'type' => 'scroll_to', 'target' => 'pricing' },
     { 'type' => 'set_calculator', 'perDay' => 40, 'mins' => 4000 }, { 'type' => 'submit_trial' },
     { 'type' => 'scroll_to', 'target' => 'javascript:alert(1)' },
     { 'type' => 'prefill_trial', 'fields' => { 'email' => 'mona@clinic.example', 'channels' => %w[whatsapp evil],
                                                'password' => 'x' } }]
  end
  let(:brain_answer) do
    { 'status' => 200, 'ok' => true, 'reply' => 'The Starter plan is 49 USD a month.', 'actions' => actions,
      'handoff' => false, 'handoff_reason' => '', 'turns_left' => 11 }
  end
  let(:posts) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    digest = Digest::SHA256.hexdigest(session)
    %w[h d].each { |w| Redis::Alfred.delete("tolzar:site_concierge:ip:127.0.0.1:#{w}") }
    Redis::Alfred.delete("tolzar:site_concierge:#{digest}")
    Redis::Alfred.delete("tolzar:site_concierge:#{digest}:handoff")
    allow(Tolzar::BrainClient).to receive(:post) do |path, body|
      posts << [path, body]
      brain_answer
    end
  end

  def ask(message, **extra)
    post '/tolzar/site/concierge',
         params: { message: message, session: session, lang: 'en', page: '/pricing', **extra },
         headers: { 'Accept' => 'application/json', 'Origin' => 'https://tolzar.com' }
  end

  it 'answers with the reply and only the allowlisted actions and values' do
    ask('How much is it for a clinic?')
    expect(response).to have_http_status(:ok)
    expect(response.headers['Access-Control-Allow-Origin']).to eq('https://tolzar.com')
    body = response.parsed_body
    expect(body['reply']).to include('49')
    expect(body['actions']).to eq([{ 'type' => 'set_industry', 'slug' => 'clinics' },
                                   { 'type' => 'scroll_to', 'target' => 'pricing' },
                                   { 'type' => 'set_calculator', 'perDay' => 40 },
                                   { 'type' => 'prefill_trial',
                                     'fields' => { 'email' => 'mona@clinic.example', 'channels' => ['whatsapp'] } }])
    expect(body['turns_left']).to eq(11)
    expect(posts.last).to eq(['/concierge/answer', { message: 'How much is it for a clinic?', messages: [] }])
  end

  it 'sends the session history on the next turn' do
    ask('Hello')
    ask('And the Team plan?')
    expect(posts.last[1][:messages].pluck('role')).to eq(%w[visitor ai])
  end

  it 'refuses bad input without calling the brain' do
    ask('x' * 501)
    expect(response).to have_http_status(:bad_request)
    ask('hi', lang: 'not a lang')
    expect(response).to have_http_status(:bad_request)
    expect(posts).to be_empty
  end

  it "passes the brain's busy, off and turn-limit answers on" do
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 503 })
    ask('Hello?')
    expect(response).to have_http_status(:service_unavailable)
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 429 })
    ask('Hello again?')
    expect(response.parsed_body['error']).to eq('rate')
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 404 })
    ask('Anyone?')
    expect(response).to have_http_status(:not_found)
  end

  it 'offers the team on a hand-off, and the agreed hand-off becomes one labelled conversation' do
    brain_answer.merge!('handoff' => true, 'handoff_reason' => 'owner_only', 'actions' => [])
    ask('Can I get 30% off?')
    expect(response.parsed_body['actions']).to eq([{ 'type' => 'handoff_human' }])

    expect do
      post '/tolzar/site/concierge/handoff', params: { session: session, email: 'mona@clinic.example', name: 'Mona' }
    end.to change(Conversation, :count).by(1)
    conversation = Conversation.last
    expect(conversation.inbox).to eq(inbox)
    expect(conversation.label_list).to include('site-concierge')
    expect(conversation.messages.first.content).to include('Visitor: Can I get 30% off?')
    expect(conversation.contact.email).to eq('mona@clinic.example')

    expect do
      post '/tolzar/site/concierge/handoff', params: { session: session }
    end.not_to change(Conversation, :count)
    expect(response.parsed_body['duplicate']).to be(true)
  end

  it 'refuses a hand-off without a chat or with a bad e-mail' do
    post '/tolzar/site/concierge/handoff', params: { session: session }
    expect(response).to have_http_status(:bad_request)
    ask('Hello')
    post '/tolzar/site/concierge/handoff', params: { session: session, email: 'not-an-email' }
    expect(response).to have_http_status(:bad_request)
  end
end
