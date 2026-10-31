require 'rails_helper'

# Tolzar own widget per-page counters: the widget ticks open / start with the visitor's token (only for the
# Tolzar-widget workspaces, origin + path only, rate-limited); administrators read pages with opens, starts, rate.
RSpec.describe 'Tolzar widget stats', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: web_widget.inbox, contact: create(:contact, account: account)) }
  let(:token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token }

  before do
    %w[open start].each do |k|
      Redis::Alfred.delete(Tolzar::WidgetStats.key(web_widget.inbox.id, Date.current, k))
    end
  end

  def tick(kind, page)
    post "/api/v1/widget/tolzar_stats?website_token=#{web_widget.website_token}", params: { kind: kind, page: page },
                                                                                   headers: { 'X-Auth-Token' => token }, as: :json
  end

  it 'counts opens and starts per page (no query string) for the Tolzar widget only' do
    tick('open', 'https://shop.test/pricing')
    expect(response).to have_http_status(:not_found)
    with_modified_env(TOLZAR_OWN_WIDGET_ACCOUNTS: account.id.to_s) do
      2.times { tick('open', 'https://shop.test/pricing?utm=a') }
      tick('start', 'https://shop.test/pricing')
      tick('open', 'https://shop.test/')
      tick('open', 'javascript:alert(1)')
      expect(response).to have_http_status(:no_content)
      get "/api/v1/accounts/#{account.id}/tolzar/widget_stats", params: { inbox_id: web_widget.inbox.id }, headers: admin.create_new_auth_token
    end
    pages = response.parsed_body['pages']
    expect(pages.first).to include('page' => 'https://shop.test/pricing', 'open' => 2, 'start' => 1, 'rate' => 50)
    expect(pages.pluck('page')).to contain_exactly('https://shop.test/pricing', 'https://shop.test/')
  end
end
