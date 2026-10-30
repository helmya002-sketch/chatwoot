require 'rails_helper'

# Queue item I (Oracle decision L-34e): fair use per plan is a SOFT limit. At 80% and 100% of the plan's monthly
# AI replies the Owner gets an in-app notice and an e-mail and Tolzar an alert, once per level per month;
# nothing is ever refused or charged. Off unless TOLZAR_FAIR_USE=true.
RSpec.describe Tolzar::FairUse do
  let(:account) { create(:account, name: 'Blue Shop') }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let(:subscription) { Tolzar::Subscription.for(account).tap { |s| s.update!(plan: 'starter', paid_until: 20.days.from_now) } }
  let(:used) { 0 }
  let(:brain) { class_double(Tolzar::BrainClient) }

  before do
    allow(brain).to receive(:get).and_return({ 'ok' => true, 'used' => used, 'month' => '2026-11', 'scope' => 'workspace' })
  end

  around do |example|
    with_modified_env(TOLZAR_FAIR_USE: 'true', TOLZAR_FAIR_USE_ALERT_TO: 'alerts@tolzar.example') { example.run }
  end

  def check
    described_class.new(subscription, brain: brain).check!
  end

  it 'reads the allowances per plan; internal has none' do
    expect(described_class.allowances).to include('starter' => 1500, 'team' => 6000, 'business' => 18_000)
    expect(described_class.allowances).not_to have_key('internal')
    expect(described_class.level(1199, 1500)).to be_nil
    expect(described_class.level(1200, 1500)).to eq('near')
    expect(described_class.level(1500, 1500)).to eq('over')
  end

  context 'when under 80%' do
    let(:used) { 100 }

    it 'stores the count and notifies nobody' do
      expect { check }.not_to have_enqueued_mail(Tolzar::FairUseMailer)
      expect(account.reload.internal_attributes['tolzar_fair_use']).to include('used' => 100, 'allowance' => 1500, 'level' => nil)
    end
  end

  context 'when at 80%' do
    let(:used) { 1200 }

    it 'notifies the Owner and Tolzar once in the month' do
      mails = have_enqueued_mail(Tolzar::FairUseMailer, :notice).once.and(have_enqueued_mail(Tolzar::FairUseMailer, :alert).once)
      expect { check }.to mails
      expect(account.reload.internal_attributes['tolzar_fair_use']).to include('level' => 'near', 'notified' => 'near')
      expect { check }.not_to have_enqueued_mail(Tolzar::FairUseMailer)
    end
  end

  it 'notifies again when the level rises, and again in a new month' do
    allow(brain).to receive(:get).and_return({ 'used' => 1300, 'month' => '2026-11' })
    check
    allow(brain).to receive(:get).and_return({ 'used' => 1600, 'month' => '2026-11' })
    expect { check }.to have_enqueued_mail(Tolzar::FairUseMailer, :notice).once
    allow(brain).to receive(:get).and_return({ 'used' => 1250, 'month' => '2026-12' })
    expect { check }.to have_enqueued_mail(Tolzar::FairUseMailer, :notice).once
  end

  it 'does nothing for an internal workspace or without a count from the brain' do
    subscription.update!(plan: 'internal')
    expect(check).to be_nil
    subscription.update!(plan: 'team')
    allow(brain).to receive(:get).and_return({ 'ok' => false })
    expect(check).to be_nil
    expect(account.reload.internal_attributes['tolzar_fair_use']).to be_nil
  end

  it 'the job does nothing while the switch is off' do
    with_modified_env(TOLZAR_FAIR_USE: 'false') do
      expect(Tolzar::BrainClient).not_to receive(:get)
      Tolzar::FairUseJob.perform_now
    end
  end
end
