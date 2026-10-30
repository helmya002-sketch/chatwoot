require 'rails_helper'

# Tolzar billing v1: trial, paid-until, pause, data hold and seat cap (TOLZAR-TRIAL-BILLING-V1-DESIGN).
RSpec.describe Tolzar::Subscription do
  let(:account) { create(:account) }
  let(:now) { Time.zone.parse('2026-11-01 12:00') }

  it 'starts a new workspace on a 30-day, 5-seat trial' do
    sub = described_class.for(account, now)
    expect(sub).to have_attributes(plan: 'trial', seat_limit: 5)
    expect(sub.trial_ends_at).to eq(now + 30.days)
    expect(sub.state(now + 29.days)).to eq('trialing')
  end

  it 'pauses when the trial ends, schedules the purge after the 30-day hold, and resumes on a plan' do
    sub = described_class.for(account, now)
    later = now + 31.days
    expect(sub.state(later)).to eq('paused')
    sub.mark_paused!(later)
    expect(sub.purge_after).to eq(later + 30.days)
    expect(sub.state(later + 30.days)).to eq('purge_scheduled')

    sub.activate!(plan: 'team', paid_until: later + 30.days)
    expect(sub.reload.state(later + 1.day)).to eq('active')
    expect(sub).to have_attributes(seat_limit: 5, paused_at: nil, purge_after: nil)
  end

  it 'gives a paid plan 3 days of grace after paid_until' do
    sub = described_class.for(account, now)
    sub.activate!(plan: 'starter', paid_until: now)
    expect(sub.state(now + 2.days)).to eq('active')
    expect(sub.state(now + 4.days)).to eq('paused')
  end

  it 'never pauses an internal workspace' do
    sub = described_class.create!(account: account, plan: 'internal', seat_limit: 1000)
    expect(sub.state(now + 10.years)).to eq('active')
    expect(sub.paused?(now + 10.years)).to be(false)
  end

  it 'extends a trial from today when it already ended' do
    sub = described_class.for(account, now)
    travel_to(now + 40.days) do
      sub.extend_trial!(days: 7)
      expect(sub.reload.trial_ends_at).to be_within(1.second).of(Time.current + 7.days)
      expect(sub.state).to eq('trialing')
    end
  end

  it 'refuses an unknown plan or currency' do
    expect(described_class.new(account: account, plan: 'gold', currency: 'USD', seat_limit: 1)).not_to be_valid
    expect(described_class.new(account: account, plan: 'team', currency: 'EUR', seat_limit: 1)).not_to be_valid
  end
end

RSpec.describe 'Tolzar billing v1 enforcement', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  around { |example| with_modified_env(TOLZAR_BILLING_ENFORCE: 'true') { example.run } }

  def reply
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Hello' }, headers: admin.create_new_auth_token, as: :json
  end

  it 'starts a trial for a new workspace and lets it work' do
    expect(Tolzar::Subscription.find_by(account_id: account.id)).to have_attributes(plan: 'trial', seat_limit: 5)
    reply
    expect(response).to have_http_status(:success)
  end

  it 'makes a paused workspace read-only, keeps reading, and resumes on a plan' do
    sub = Tolzar::Subscription.find_by(account_id: account.id)
    sub.update!(trial_ends_at: 1.day.ago)
    reply
    expect(response).to have_http_status(:payment_required)
    expect(response.parsed_body['error']).to eq('workspace_paused')
    expect(sub.reload.purge_after).to be_within(1.minute).of(Time.current + 30.days)

    get "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)

    sub.activate!(plan: 'starter', paid_until: 30.days.from_now)
    reply
    expect(response).to have_http_status(:success)
  end

  it 'refuses an invite beyond the seat limit' do
    Tolzar::Subscription.find_by(account_id: account.id).update!(seat_limit: 1)
    admin
    post "/api/v1/accounts/#{account.id}/agents", params: { name: 'New', email: 'new@example.com', role: 'agent' },
                                                  headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:payment_required)
    expect(response.parsed_body['error']).to eq('seat_limit_reached')
  end

  it 'refuses nothing while enforcement is off' do
    Tolzar::Subscription.find_by(account_id: account.id).update!(trial_ends_at: 1.day.ago)
    with_modified_env(TOLZAR_BILLING_ENFORCE: nil) { reply }
    expect(response).to have_http_status(:success)
  end
end
