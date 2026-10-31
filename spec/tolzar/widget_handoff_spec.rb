require 'rails_helper'

# Tolzar own widget hand-off links: the owner sets WhatsApp / Instagram / Telegram per website inbox; the Tolzar
# widget page carries them as wa.me / ig.me / t.me links.
RSpec.describe 'Tolzar widget hand-off', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/tolzar/widget_handoff" }

  it 'lets the owner save valid handles and numbers, and refuses bad ones' do
    post url, params: { inbox_id: web_widget.inbox.id, whatsapp: '+20 100 123 4567' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post url, params: { inbox_id: web_widget.inbox.id, whatsapp: '0100' }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, params: { inbox_id: web_widget.inbox.id, whatsapp: '+20 100 123 4567', instagram: '@nile.bikes', telegram: 'nilebikes' },
              headers: owner.create_new_auth_token, as: :json
    expect(response.parsed_body['links']).to contain_exactly(
      { 'channel' => 'whatsapp', 'url' => 'https://wa.me/201001234567' },
      { 'channel' => 'instagram', 'url' => 'https://ig.me/m/nile.bikes' },
      { 'channel' => 'telegram', 'url' => 'https://t.me/nilebikes' }
    )
    get url, params: { inbox_id: web_widget.inbox.id }, headers: admin.create_new_auth_token
    expect(response.parsed_body.dig('values', 'telegram')).to eq('nilebikes')
  end

  it 'puts the links in the Tolzar widget page config' do
    Tolzar::WidgetHandoff.save!(web_widget.inbox, { 'whatsapp' => '+201001234567' })
    config = Tolzar::OwnWidget.page_config(web_widget, nil, 'tok')
    expect(config.dig(:channel, :handoff)).to eq([{ channel: 'whatsapp', url: 'https://wa.me/201001234567' }])
  end
end
