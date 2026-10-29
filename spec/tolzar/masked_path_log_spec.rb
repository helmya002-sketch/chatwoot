require 'rails_helper'

# The workspace Meta app's webhook token is in its URL path; Rails' request log line must not print it.
RSpec.describe TolzarMaskedPathLog do
  let(:token) { 'a1' * 16 }

  it "masks the token in Rails' Started line" do
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/tolzar/meta/hook/#{token}", method: 'POST'))
    line = Rails::Rack::Logger.new(->(_env) { [200, {}, []] }).send(:started_request_message, request)
    expect(line).to include('/tolzar/meta/hook/[FILTERED]')
    expect(line).not_to include(token)
  end

  it 'leaves other paths alone' do
    expect(described_class.mask('/api/v1/accounts/1/conversations')).to eq('/api/v1/accounts/1/conversations')
  end
end
