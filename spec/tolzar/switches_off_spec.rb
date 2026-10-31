require 'rails_helper'

# Every Tolzar feature switch, OFF (round 4, c84; the Oracle's ask before a big patch): with nothing set, each
# feature's API answers 404 or leaves its data out, the old page / mail is served, and the dashboard flags that drive
# the new screens are false, so the UI stays hidden too. One row per switch; each row also proves the switch exists
# by turning it ON for this workspace and seeing the feature answer. Config variables (URLs, ids, secrets) are not
# switches and are not listed.
RSpec.describe 'Tolzar feature switches, off by default', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:headers) { owner.create_new_auth_token }
  let(:api) { "/api/v1/accounts/#{account.id}/tolzar" }

  feature_switches = %w[
    TOLZAR_BOOKINGS_ACCOUNTS TOLZAR_BOOKING_DOCS_ACCOUNTS TOLZAR_BOOKING_CONNECTOR TOLZAR_TIKTOK_CRM_EVENTS
    TOLZAR_TIKTOK_COMMENTS TOLZAR_TIKTOK_COMMENT_REPLIES TOLZAR_LEAD_INTAKE TOLZAR_OWN_WIDGET_ACCOUNTS
    TOLZAR_NEW_UI_ACCOUNTS TOLZAR_NEW_UI_AUTH TOLZAR_NEW_EMAILS TOLZAR_PWA_ACCOUNTS TOLZAR_TOPBAR_ACCOUNTS
    TOLZAR_META_HUMAN_AGENT TOLZAR_ANNOUNCEMENTS TOLZAR_AUTO_PROVISION TOLZAR_BILLING_ENFORCE TOLZAR_MCP_PUBLIC
    TOLZAR_SUPERADMIN_2FA_REQUIRED TOLZAR_DIGEST_ACCOUNTS TOLZAR_WEEKLY_REPORT_ACCOUNTS TOLZAR_COLLISION_GUARD_ACCOUNTS
    TOLZAR_INBOX_TOOLS_ACCOUNTS TOLZAR_BRAIN_USER_IDS
  ].freeze

  it 'starts with every feature switch unset in this environment' do
    expect(feature_switches.select { |name| ENV[name].present? }).to eq([])
  end

  {
    'TOLZAR_BOOKINGS_ACCOUNTS' => '/bookings',
    'TOLZAR_BOOKING_DOCS_ACCOUNTS' => '/documents',
    'TOLZAR_BOOKING_CONNECTOR' => '/booking_connector',
    'TOLZAR_TIKTOK_CRM_EVENTS' => '/tiktok_crm',
    'TOLZAR_INBOX_TOOLS_ACCOUNTS' => '/outcome_reasons'
  }.each do |switch, path|
    it "answers 404 for #{path} while #{switch} is off, and serves it when on" do
      get "#{api}#{path}", headers: headers
      expect(response).to have_http_status(:not_found)
      with_modified_env(switch => account.id.to_s) do
        get "#{api}#{path}", headers: headers
        expect(response).not_to have_http_status(:not_found)
      end
    end
  end

  it 'keeps the Results team and reasons cards hidden while TOLZAR_INBOX_TOOLS_ACCOUNTS is off' do
    %w[/team_leaderboard /channel_breakdown /outcome_reasons /contacts/0/timeline].each do |path|
      get "#{api}#{path}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'keeps booking results hidden while both booking switches are off' do
    get "#{api}/booking_results", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'gives no lead URLs while TOLZAR_LEAD_INTAKE is off' do
    create(:channel_api, account: account)
    get "#{api}/lead_intake", headers: headers
    expect(response.parsed_body['enabled']).to be(false)
    expect(response.parsed_body['inboxes'].pluck('url').compact).to eq([])
  end

  it 'keeps the new screens off in the account the dashboard reads' do
    get "/api/v1/accounts/#{account.id}", headers: headers, as: :json
    expect(response.parsed_body).to include('tolzar_new_ui' => false, 'tolzar_pwa' => false, 'tolzar_meta_human_agent' => false,
                                            'tolzar_collision_guard' => false)
  end

  it 'sends no top-bar counts or AI state while TOLZAR_TOPBAR_ACCOUNTS is off' do
    get "#{api}/briefing", headers: headers
    expect(response.parsed_body.keys).not_to include('now', 'ai', 'day')
  end

  it 'serves the old widget page, the old sign-in look and the old account mails' do
    widget = create(:channel_widget, account: account)
    get '/widget', params: { website_token: widget.website_token }
    expect(response.body).not_to include('tz-widget-config')
    expect(widget.web_widget_script).to include('/packs/js/sdk.js')

    get '/app/login'
    expect(response.body).to include("tolzarNewAuth: 'false'")

    mail = Devise::Mailer.reset_password_instructions(owner, 'tok')
    expect((mail.html_part || mail).body.decoded).not_to include('Choose a new password')
  end

  it 'never tags a Messenger reply with HUMAN_AGENT while TOLZAR_META_HUMAN_AGENT is off' do
    stub_request(:post, /graph.facebook.com/)
    inbox = create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 2.days.ago)
    reply = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: owner)
    expect(Tolzar::MetaHumanAgent.tag?(reply)).to be(false)
    expect(Conversations::MessageWindowService.new(conversation).can_reply?).to be(false)
  end

  it 'opens no platform announcements while TOLZAR_ANNOUNCEMENTS is off' do
    expect(Tolzar::Announcements.enabled?).to be(false)
  end
end
