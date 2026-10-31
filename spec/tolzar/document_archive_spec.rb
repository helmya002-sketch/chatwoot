require 'rails_helper'
require 'rubygems/package'

# Tolzar booking documents: a period's issued / cancelled documents as PDFs + register.csv in one .tar.gz (admins);
# the contact filter for the sidebar card; nothing is exported when the renderer is not there.
RSpec.describe 'Tolzar document archive', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Sara') }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar/documents" }

  around { |example| with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run } }

  def issued_doc
    doc = Tolzar::Document.create!(account: account, contact: contact, doc_type: 'voucher', currency: 'EUR',
                                   spec: { lines: [{ type: 'service', description: 'Boat day', unit_price: '60' }] })
    doc.issue!(by: admin)
    doc
  end

  def entries(gz)
    out = {}
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(gz))) { |tar| tar.each { |e| out[e.full_name] = e.read } }
    out
  end

  it 'archives the PDFs and the register for the period' do
    doc = issued_doc
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 200, 'pdf_b64' => Base64.strict_encode64('%PDF-1.7 x') })
    get "#{base}/export_pdfs", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    files = entries(response.body)
    expect(files.keys).to contain_exactly("#{doc.number}.pdf", 'register.csv')
    expect(files["#{doc.number}.pdf"]).to eq('%PDF-1.7 x')
    expect(files['register.csv']).to include(doc.number, 'Sara')
  end

  it 'exports nothing when the renderer is not available, and filters the register by contact' do
    issued_doc
    allow(Tolzar::BrainClient).to receive(:post).and_return({ 'status' => 503 })
    get "#{base}/export_pdfs", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:service_unavailable)
    other = create(:contact, account: account)
    get base, params: { contact_id: other.id }, headers: admin.create_new_auth_token
    expect(response.parsed_body['documents']).to be_empty
    get base, params: { contact_id: contact.id }, headers: admin.create_new_auth_token
    expect(response.parsed_body['documents'].size).to eq(1)
  end
end
