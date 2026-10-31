require 'rails_helper'

# Tolzar quote acceptance link (round 4, D2): Tolzar::Document + TOLZAR_QUOTE_ACCEPT_ACCOUNTS workspaces; any
# member gets the link of an issued quote; Accept makes one draft confirmation (idempotent), never a send; void,
# expired and non-quote documents are no longer valid; 404 for a bad token or the switch off.
RSpec.describe 'Tolzar quote acceptance', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:switches) { { TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s, TOLZAR_QUOTE_ACCEPT_ACCOUNTS: account.id.to_s } }
  let(:spec) do
    { lines: [{ type: 'service', description: 'Boat day', qty: 2, unit_price: '60' }],
      valid_until: (Date.current + 10).iso8601 }
  end

  def quote(doc_type: 'quote', spec_value: spec)
    doc = Tolzar::Document.create!(account: account, conversation: conversation, contact: conversation.contact,
                                   doc_type: doc_type, currency: 'EUR', spec: spec_value)
    doc.issue!(by: agent)
    doc
  end

  def link_path(doc)
    post "/api/v1/accounts/#{account.id}/tolzar/documents/#{doc.id}/accept_link", headers: agent.create_new_auth_token
    URI.parse(response.parsed_body['url']).path
  end

  it 'is 404 while the switch is off, and for a bad token' do
    doc = quote
    post "/api/v1/accounts/#{account.id}/tolzar/documents/#{doc.id}/accept_link", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    path = with_modified_env(**switches) { link_path(doc) }

    get path
    expect(response).to have_http_status(:not_found)
    with_modified_env(TOLZAR_BOOKING_DOCS_ACCOUNTS: account.id.to_s) do
      get path
      expect(response).to have_http_status(:not_found)
    end

    with_modified_env(**switches) do
      get "/tz/quote/#{doc.id}/#{'a' * 64}"
      expect(response).to have_http_status(:not_found)
      post "/tz/quote/#{doc.id}/#{'a' * 64}"
      expect(response).to have_http_status(:not_found)
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(doc.number, 'Boat day', 'EUR 120.00', (Date.current + 10).iso8601)
    end
  end

  it 'accepts once: one draft confirmation copying the quote, the same on a second Accept' do
    doc = quote
    with_modified_env(**switches) do
      path = link_path(doc)
      expect { post path }.to change(Tolzar::Document.where(doc_type: 'confirmation'), :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('You have accepted this quote')

      confirmation = Tolzar::Document.where(doc_type: 'confirmation').last
      expect(confirmation).to have_attributes(status: 'draft', currency: 'EUR', conversation_id: conversation.id,
                                              total_cents: 12_000, created_by_id: nil)
      expect(confirmation.spec['lines'].first['description']).to eq('Boat day')
      expect(account.reload.settings['tolzar_quote_links'][doc.id.to_s]).to include('confirmation_id' => confirmation.id)
      expect(account.settings['tolzar_quote_links'][doc.id.to_s]['accepted_at']).to be_present

      expect { post path }.not_to change(Tolzar::Document, :count)
      expect(Tolzar::QuoteAcceptance.accept!(doc.reload)).to eq(confirmation)
    end
  end

  it 'does not accept a void, expired or non-quote document' do
    with_modified_env(**switches) do
      voided = quote
      path = link_path(voided)
      voided.void!(reason: 'customer changed plans', by: agent)
      expect { post path }.not_to change(Tolzar::Document, :count)
      expect(response.body).to include('no longer valid')
      expect(Tolzar::QuoteAcceptance.accepted?(voided.reload)).to be(false)

      expired = quote(spec_value: spec.merge(valid_until: (Date.current - 1).iso8601))
      post "/api/v1/accounts/#{account.id}/tolzar/documents/#{expired.id}/accept_link", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect { Tolzar::QuoteAcceptance.accept!(expired) }.to raise_error(Tolzar::QuoteAcceptance::Refused)

      voucher = quote(doc_type: 'voucher')
      post "/api/v1/accounts/#{account.id}/tolzar/documents/#{voucher.id}/accept_link", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      get "/tz/quote/#{voucher.id}/#{Tolzar::QuoteAcceptance.token(voucher)}"
      expect(response.body).to include('no longer valid')
      expect(Tolzar::Document.where(doc_type: 'confirmation').count).to eq(0)
    end
  end
end
