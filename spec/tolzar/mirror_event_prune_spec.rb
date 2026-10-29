require 'rails_helper'

# respond.io mirror payloads (contact PII, message text) are emptied 180 days after projection; the
# row stays so a redelivery is still recognised.
RSpec.describe Tolzar::MirrorEventPruneJob do
  def event(id, processed_at)
    Tolzar::MirrorEvent.create!(tenant: 'aquarius', event_id: id, payload: { 'contact' => { 'phone' => '+201' } },
                                received_at: processed_at || Time.current, processed_at: processed_at)
  end

  it 'empties old projected payloads only and keeps the rows' do
    old = event('e-old', 200.days.ago)
    recent = event('e-new', 10.days.ago)
    pending = event('e-pending', nil)
    expect(described_class.perform_now).to eq(1)
    expect(old.reload.payload).to eq({})
    expect(recent.reload.payload).to include('contact')
    expect(pending.reload.payload).to include('contact')
    expect(Tolzar::MirrorEvent.where(event_id: 'e-old')).to exist
  end

  it 'is scheduled daily' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    expect(schedule['tolzar_mirror_event_prune_job']).to include('class' => 'Tolzar::MirrorEventPruneJob', 'cron' => '30 5 * * * UTC')
  end
end
