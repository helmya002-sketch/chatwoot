require 'rails_helper'

# Launch channels plan (31 Oct, T2/W4): a TikTok or WhatsApp Cloud inbox gets the brain like any other inbox
# (B2 auto-provisioning), and the brain's shadow drafts, which are private notes, never leave Tolzar on
# either channel.
RSpec.describe 'Tolzar launch channels: TikTok and WhatsApp Cloud' do
  let(:account) { create(:account) }
  let(:brain_bot) { create(:agent_bot, account: nil, outgoing_url: 'http://tolzar-brain:8080/hooks/chatwoot') }
  let(:env) do
    { TOLZAR_AUTO_PROVISION: 'true', TOLZAR_BRAIN_BOT_ID: brain_bot.id.to_s, TOLZAR_BRAIN_URL: 'http://tolzar-brain:8080',
      BRAIN_WEBHOOK_SECRET: 'master-secret-for-tests' }
  end
  let(:tiktok_inbox) { create(:channel_tiktok, account: account).inbox }
  let(:whatsapp_inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end

  around { |example| with_modified_env(env) { example.run } }

  def shadow_note(inbox)
    contact = create(:contact, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true,
                     content: '[Tolzar, shadow] would reply: Hello!')
  end

  it 'attaches the system brain bot to a new TikTok inbox and a new WhatsApp Cloud inbox' do
    expect(tiktok_inbox.reload.agent_bot).to eq(brain_bot)
    expect(whatsapp_inbox.reload.agent_bot).to eq(brain_bot)
  end

  it 'never sends a private note to TikTok' do
    note = shadow_note(tiktok_inbox)
    expect(HTTParty).not_to receive(:post)
    expect(HTTParty).not_to receive(:get)
    SendReplyJob.perform_now(note.id)
  end

  it 'never sends a private note to WhatsApp' do
    note = shadow_note(whatsapp_inbox)
    expect(HTTParty).not_to receive(:post)
    SendReplyJob.perform_now(note.id)
  end
end
