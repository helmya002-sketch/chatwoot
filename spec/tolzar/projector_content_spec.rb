require 'rails_helper'

# Tolzar mirror projector: what a respond.io message becomes in Tolzar (no sends, ever).
RSpec.describe Tolzar::Mirror::Projector do
  let(:event) { Struct.new(:payload, :tenant, :event_type).new({}, 'aquarius', 'message.received') }
  let(:projector) { described_class.new(event: event) }

  def content(inner)
    projector.send(:message_content, inner)
  end

  def attrs(msg, inner)
    projector.send(:message_attributes, msg, inner)
  end

  it 'keeps plain text' do
    expect(content({ 'type' => 'text', 'text' => 'Hello' })).to eq('Hello')
  end

  it 'carries an email subject and body and cuts the quoted thread' do
    body = "We are 2 divers in Makadi.\n\nOn Mon, 1 Oct Aquarius wrote:\n> old text"
    out = content({ 'type' => 'email', 'subject' => 'Diving next week', 'message' => body })
    expect(out).to eq("Subject: Diving next week\n\nWe are 2 divers in Makadi.")
  end

  it 'labels attachments and keeps only their link and metadata' do
    inner = { 'type' => 'attachment', 'attachment' => { 'type' => 'audio', 'url' => 'https://cdn.chatapi.net/a.opus',
                                                        'mimeType' => 'audio/ogg', 'size' => 31_000 } }
    expect(content(inner)).to eq('[voice note]')
    a = attrs({ 'timestamp' => 1 }, inner)
    expect(a[:tolzar_attachment]).to include(type: 'audio', url: 'https://cdn.chatapi.net/a.opus', mime: 'audio/ogg')
    expect(a[:external_created_at]).to eq(1)
  end

  it 'reads the real lifecycle, not the conversation status' do
    out = projector.send(:rio_attrs, { 'id' => 9, 'lifecycle' => 'Customer Won', 'status' => 'open' })
    expect(out).to include('rio_lifecycle' => 'Customer Won', 'rio_status' => 'open')
  end
end
