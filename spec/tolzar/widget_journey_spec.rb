require 'rails_helper'

# Tolzar's own website widget, end to end (round 4, c76): one visitor's whole journey on a workspace that uses our
# widget, through the same endpoints the widget calls. Open the widget, fill in the pre-chat details and write
# (the page they are on goes along, without its query), get a team reply, get a choice and answer it, and see
# the business's "continue on" links. Everything is a request; nothing is sent anywhere outside Tolzar.
RSpec.describe 'Tolzar own widget: a visitor journey', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:token_header) { { 'X-Auth-Token' => @token } }

  around { |example| with_modified_env(TOLZAR_OWN_WIDGET_ACCOUNTS: account.id.to_s) { example.run } }

  before do
    create(:inbox_member, user: agent, inbox: web_widget.inbox)
    Tolzar::WidgetHandoff.save!(web_widget.inbox, { 'whatsapp' => '+201001234567' })
  end

  def open_widget
    get '/widget', params: { website_token: web_widget.website_token }
    expect(response).to have_http_status(:ok)
    json = response.body[%r{<script type="application/json" id="tz-widget-config">(.*?)</script>}m, 1]
    JSON.parse(CGI.unescapeHTML(json.to_s))
  end

  def widget_messages
    get '/api/v1/widget/messages', params: { website_token: web_widget.website_token }, headers: token_header, as: :json
    response.parsed_body['payload']
  end

  it 'takes a visitor from opening the widget to answering a choice' do
    config = open_widget
    @token = config['authToken']
    expect(@token).to be_present
    expect(config.dig('channel', 'handoff').to_s).to include('https://wa.me/201001234567')

    post '/api/v1/widget/conversations',
         params: { website_token: web_widget.website_token, contact: { name: 'Mona', email: 'mona@tolzar.com' },
                   message: { content: 'Do you have a boat day on Saturday?', referer_url: 'https://shop.example/tours' } },
         headers: token_header, as: :json
    expect(response).to have_http_status(:ok)
    conversation = web_widget.inbox.conversations.last
    expect(conversation.contact.name).to eq('Mona')
    first = conversation.messages.incoming.last
    expect(first.content).to eq('Do you have a boat day on Saturday?')
    page = [first.content_attributes, first.additional_attributes, conversation.additional_attributes].map(&:to_s).join
    expect(page).to include('shop.example/tours') # the page the visitor was on goes along with the message

    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Yes, Saturday at 9.' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(widget_messages.pluck('content')).to include('Yes, Saturday at 9.')

    choice = conversation.messages.create!(
      account: account, inbox: web_widget.inbox, sender: agent, message_type: :outgoing, content: 'Which time suits you?',
      content_type: :input_select, content_attributes: { items: [{ title: '9:00', value: '9' }, { title: '13:00', value: '13' }] }
    )
    shown = widget_messages.find { |m| m['id'] == choice.id }
    expect(shown['content_type']).to eq('input_select')

    patch "/api/v1/widget/messages/#{choice.id}",
          params: { website_token: web_widget.website_token, message: { submitted_values: [{ title: '9:00', value: '9' }] } },
          headers: token_header, as: :json
    expect(response).to have_http_status(:ok)
    expect(choice.reload.content_attributes['submitted_values'].first['value']).to eq('9')
  end

  it 'keeps another workspace on the old widget page' do
    with_modified_env(TOLZAR_OWN_WIDGET_ACCOUNTS: '') do
      get '/widget', params: { website_token: web_widget.website_token }
      expect(response.body).not_to include('tz-widget-config')
    end
  end
end
