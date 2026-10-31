require 'rails_helper'

# Tolzar sign-in pages in the new look (round 4, c82): only when TOLZAR_NEW_UI_AUTH=true does the page tell the
# sign-in app to add body.tz-auth; anything else (unset, "1", "yes") keeps the old look.
RSpec.describe 'Tolzar sign-in look', type: :request do
  it 'stays off unless TOLZAR_NEW_UI_AUTH is exactly true' do
    get '/app/login'
    expect(response.body).to include("tolzarNewAuth: 'false'")
    with_modified_env(TOLZAR_NEW_UI_AUTH: 'yes') do
      get '/app/login'
      expect(response.body).to include("tolzarNewAuth: 'false'")
    end
    with_modified_env(TOLZAR_NEW_UI_AUTH: 'true') do
      get '/app/login'
      expect(response.body).to include("tolzarNewAuth: 'true'")
    end
  end
end
