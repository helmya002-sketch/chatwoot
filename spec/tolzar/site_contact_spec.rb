require 'rails_helper'

# Tolzar: the marketing site's trial / contact form lands as a conversation in Tolzar's own API inbox.
RSpec.describe 'Tolzar site contact form', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:env) do
    { TOLZAR_CONTACT_INBOX_ID: inbox.id.to_s, TOLZAR_CONTACT_ORIGINS: 'https://tolzar.com',
      TOLZAR_CONTACT_REDIRECT: 'https://tolzar.com/thanks' }
  end
  let(:form) { { name: 'Mona Adel', email: 'Mona@Example.com', company: 'Blue Hotel', topic: 'trial', message: 'We want a trial.' } }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Redis::Alfred.delete('tolzar:site_contact:ip:127.0.0.1')
    Redis::Alfred.delete("tolzar:site_contact:day:#{Time.current.utc.to_date}")
  end

  it 'creates a contact and an incoming conversation, then sends a plain form to the thank-you page' do
    expect { post '/tolzar/site/contact', params: form }.to change(inbox.conversations, :count).by(1)
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to('https://tolzar.com/thanks')
    conversation = inbox.conversations.last
    expect(conversation.contact).to have_attributes(name: 'Mona Adel', email: 'mona@example.com')
    expect(conversation.additional_attributes).to include('source' => 'tolzar_site_form', 'topic' => 'trial')
    message = conversation.messages.last
    expect(message).to be_incoming
    expect(message.content).to include('Website form: trial', 'Company: Blue Hotel', 'We want a trial.')
  end

  it 'answers fetch() with JSON and CORS for an allowed origin only' do
    post '/tolzar/site/contact', params: form.to_json,
                                 headers: { 'Content-Type' => 'application/json', 'Origin' => 'https://tolzar.com' }
    expect(response.parsed_body).to eq('ok' => true)
    expect(response.headers['Access-Control-Allow-Origin']).to eq('https://tolzar.com')

    post '/tolzar/site/contact', params: form.to_json,
                                 headers: { 'Content-Type' => 'application/json', 'Origin' => 'https://evil.example' }
    expect(response.headers['Access-Control-Allow-Origin']).to be_nil
  end

  it 'reuses the contact with the same email' do
    2.times { post '/tolzar/site/contact', params: form }
    expect(account.contacts.where(email: 'mona@example.com').count).to eq(1)
    expect(inbox.conversations.count).to eq(2)
  end

  it 'says thanks to the honeypot and stores nothing' do
    expect { post '/tolzar/site/contact', params: form.merge(website: 'http://spam.example') }
      .not_to change(Conversation, :count)
    expect(response).to have_http_status(:see_other)
  end

  it 'refuses a missing or invalid email' do
    post '/tolzar/site/contact', params: form.merge(email: 'not-an-email'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('ok' => false, 'error' => 'invalid_email')
  end

  it 'limits each IP to 5 forms an hour' do
    5.times { post '/tolzar/site/contact', params: form }
    expect { post '/tolzar/site/contact', params: form }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'answers the CORS preflight for an allowed origin' do
    process :options, '/tolzar/site/contact', headers: { 'Origin' => 'https://tolzar.com' }
    expect(response).to have_http_status(:no_content)
    expect(response.headers['Access-Control-Allow-Methods']).to include('POST')
  end

  context 'without a configured inbox' do
    let(:env) { { TOLZAR_CONTACT_INBOX_ID: '' } }

    it 'is switched off' do
      post '/tolzar/site/contact', params: form
      expect(response).to have_http_status(:not_found)
    end
  end
end
