require 'rails_helper'

# Tolzar's own widget, phase 1: /widget renders the Tolzar app only for TOLZAR_OWN_WIDGET_ACCOUNTS; the old app
# everywhere else; the visitor's token works in both; the config is JSON data, never inline JS.
describe 'Tolzar own widget', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account, welcome_title: '</script><script>alert(1)</script>') }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token }

  def open_widget
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
  end

  it 'serves the old widget while the workspace is not listed' do
    open_widget
    expect(response).to be_successful
    expect(response.body).to include('window.chatwootWebChannel')
    expect(response.body).not_to include('tz-widget-config')
  end

  it 'serves the Tolzar app with the same visitor token for a listed workspace' do
    with_modified_env(TOLZAR_OWN_WIDGET_ACCOUNTS: account.id.to_s) do
      open_widget
    end
    expect(response).to be_successful
    body = response.body
    expect(body).to include('id="tz-widget-config"', 'id="tz-widget"')
    expect(body).not_to include('window.chatwootWebChannel')
    json = body[%r{<script type="application/json" id="tz-widget-config">(.*?)</script>}m, 1]
    config = JSON.parse(json)
    expect(config['authToken']).to eq(token)
    expect(config['pubsubToken']).to eq(contact_inbox.pubsub_token)
    expect(config.dig('channel', 'websiteToken')).to eq(web_widget.website_token)
    expect(body).not_to include('<script>alert(1)</script>')
  end
end
