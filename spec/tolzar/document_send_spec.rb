require 'rails_helper'

# Tolzar booking documents: a staff member's Send puts the issued document, rendered by the brain as a PDF, into
# its conversation as an outgoing message with the PDF attached; drafts and unlinked documents are refused.
RSpec.describe 'Tolzar document send', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:spec) { { lines: [{ type: 'service', description: 'Boat day', qty: 1, unit_price: '60' }] } }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar/documents" }
  let(:pdf) { "%PDF-1.7\n%fake one-page document\n" }

  around { |example| with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run } }

  def document(status: :issued, conv: conversation)
    doc = Tolzar::Document.create!(account: account, conversation: conv, contact: conv&.contact, doc_type: 'voucher',
                                   currency: 'EUR', spec: spec)
    doc.issue!(by: agent) if status == :issued
    doc
  end

  it 'sends the issued document as a PDF attachment from the staff member, and records it' do
    doc = document
    allow(Tolzar::BrainClient).to receive(:post).with('/documents/render', anything, account_id: account.id)
                                                .and_return({ 'status' => 200, 'pdf_b64' => Base64.strict_encode64(pdf), 'pages' => 1 })
    expect { post "#{base}/#{doc.id}/send", headers: agent.create_new_auth_token }.to change(conversation.messages, :count).by(1)
    expect(response).to have_http_status(:ok)
    message = conversation.messages.last
    expect(message).to have_attributes(message_type: 'outgoing', sender: agent, content: "Voucher #{doc.number}")
    attachment = message.attachments.sole
    expect(attachment.file.filename.to_s).to eq("#{doc.number}.pdf")
    expect(attachment.file.download).to eq(pdf)
    expect(doc.reload.history.last).to include('action' => 'sent', 'message_id' => message.id)
  end

  it 'refuses a draft, an unlinked document and a renderer that is not there' do
    post "#{base}/#{document(status: :draft).id}/send", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('only an issued document')
    post "#{base}/#{document(conv: nil).id}/send", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('not linked')
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 503 })
    expect { post "#{base}/#{document.id}/send", headers: agent.create_new_auth_token }.not_to change(Message, :count)
    expect(response.parsed_body['error']).to include('not available')
  end
end
