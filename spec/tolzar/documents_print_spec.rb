require 'rails_helper'

# Tolzar booking documents, step 2: the printable page (escaped, a DRAFT / CANCELLED stamp, totals and balance)
# and the owner's number prefixes.
RSpec.describe 'Tolzar booking documents print and prefixes', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/tolzar" }
  let(:spec) do
    { title: '<script>x</script>Booking', lines: [{ type: 'service', description: 'Boat day', qty: 2, unit_price: '60' }],
      payments: [{ amount: '50' }] }
  end

  around { |example| with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) { example.run } }

  it 'prints a draft with its stamp, escaped content, total and balance' do
    post "#{base}/documents", params: { doc_type: 'confirmation', spec: spec }, headers: agent.create_new_auth_token, as: :json
    id = response.parsed_body.dig('document', 'id')
    get "#{base}/documents/#{id}/print", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('DRAFT', 'Boat day', '120.00', '70.00')
    expect(response.body).not_to include('<script>x</script>')
  end

  it 'lets only the owner change the prefixes, and numbers follow them' do
    post "#{base}/documents_settings", params: { prefixes: { voucher: 'NB' } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{base}/documents_settings", params: { prefixes: { voucher: 'x!' } }, headers: owner.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/documents_settings", params: { prefixes: { voucher: 'nbk' } }, headers: owner.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('prefixes', 'voucher')).to eq('NBK')
    expect(response.parsed_body.dig('prefixes', 'quote')).to eq('QTE')
    post "#{base}/documents", params: { doc_type: 'voucher', spec: spec }, headers: agent.create_new_auth_token, as: :json
    post "#{base}/documents/#{response.parsed_body.dig('document', 'id')}/issue", headers: agent.create_new_auth_token
    expect(response.parsed_body.dig('document', 'number')).to start_with('NBK-')
  end
end
