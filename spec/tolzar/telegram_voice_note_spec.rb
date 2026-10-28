require 'rails_helper'

# Licence work: the dashboard no longer encodes MP3 (lamejs is LGPL-3.0), so Telegram voice notes arrive as
# OGG/Opus. Telegram's media-group audio items are MP3/M4A only; OGG/Opus must go through sendVoice.
RSpec.describe Telegram::SendAttachmentsService do
  let(:channel) { create(:channel_telegram) }
  let(:message) { build(:message, conversation: create(:conversation, inbox: channel.inbox)) }
  let(:telegram_api_url) { channel.telegram_api_url }

  before do
    allow(channel).to receive(:chat_id).and_return('chat123')
    stub_request(:post, "#{telegram_api_url}/sendVoice")
      .to_return(status: 200, body: { ok: true, result: { message_id: 'voice' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, "#{telegram_api_url}/sendMediaGroup")
      .to_return(status: 200, body: { ok: true, result: [{ message_id: 'media' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def attach(type, filename, content_type)
    attachment = message.attachments.new(account_id: message.account_id, file_type: type)
    attachment.file.attach(io: Rails.root.join("spec/assets/#{filename}").open, filename: filename, content_type: content_type)
  end

  it 'sends an OGG/Opus voice note with sendVoice, not as a media-group audio item' do
    attach('audio', 'sample.ogg', 'audio/ogg')
    message.save!

    expect(described_class.new(message: message).perform).to eq('voice')
    expect(a_request(:post, "#{telegram_api_url}/sendVoice").with { |req| req.body.include?('voice=') && req.body.include?('chat123') })
      .to have_been_made.once
    expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")).not_to have_been_made
  end

  it 'keeps MP3 audio in a media group' do
    attach('audio', 'sample.mp3', 'audio/mpeg')
    message.save!

    expect(described_class.new(message: message).perform).to eq('media')
    expect(a_request(:post, "#{telegram_api_url}/sendVoice")).not_to have_been_made
  end
end
