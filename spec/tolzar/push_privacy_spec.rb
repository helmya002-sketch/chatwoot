require 'rails_helper'

# Tolzar push on the phone (round 4, c64): for TOLZAR_PWA_ACCOUNTS workspaces the push says who, never what, and
# nothing is pushed during the person's quiet hours. Other workspaces are unchanged.
RSpec.describe Tolzar::PushPrivacy do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Mona Adel') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:notification) do
    create(:notification, user: user, account: account, primary_actor: conversation, notification_type: 'conversation_assignment')
  end

  def quiet(from, to, tz: 'UTC', on: true)
    user.update!(ui_settings: { 'tolzar_quiet_hours' => { 'on' => on, 'from' => from, 'to' => to, 'tz' => tz } })
    user
  end

  it 'names who the push is about, never what they wrote' do
    expect(described_class.title(notification)).to eq('Assigned to you: Mona Adel')
    notification.update!(notification_type: 'conversation_creation')
    expect(described_class.title(notification)).to eq('New conversation from Mona Adel')
  end

  it 'keeps quiet hours, overnight too, in the person\'s own time zone' do
    noon = Time.utc(2026, 11, 2, 12, 0)
    night = Time.utc(2026, 11, 2, 23, 30)
    early = Time.utc(2026, 11, 3, 5, 0)
    expect(described_class.quiet?(quiet('22:00', '07:00'), night)).to be(true)
    expect(described_class.quiet?(quiet('22:00', '07:00'), early)).to be(true)
    expect(described_class.quiet?(quiet('22:00', '07:00'), noon)).to be(false)
    expect(described_class.quiet?(quiet('12:00', '13:00'), noon)).to be(true)
    # Noon UTC is 21:00 in Tokyo: outside 22:00–07:00 there, inside 20:00–23:00.
    expect(described_class.quiet?(quiet('22:00', '07:00', tz: 'Asia/Tokyo'), noon)).to be(false)
    expect(described_class.quiet?(quiet('20:00', '23:00', tz: 'Asia/Tokyo'), noon)).to be(true)
    expect(described_class.quiet?(quiet('22:00', '07:00', on: false), night)).to be(false)
    expect(described_class.quiet?(quiet('9pm', '07:00'), night)).to be(false)
    expect(described_class.quiet?(quiet('08:00', '08:00'), noon)).to be(false)
  end

  describe 'the push service' do
    before do
      allow(WebPush).to receive(:payload_send).and_return(true)
      create(:notification_subscription, user: user)
    end

    it 'sends the private title and stays quiet in quiet hours for a switched-on workspace' do
      with_modified_env(VAPID_PUBLIC_KEY: 'test', TOLZAR_PWA_ACCOUNTS: account.id.to_s) do
        Notification::PushNotificationService.new(notification: notification).perform
        expect(WebPush).to have_received(:payload_send).with(hash_including(message: include('Assigned to you: Mona Adel'))).once

        now = Time.current.utc
        quiet((now - 1.hour).strftime('%H:%M'), (now + 1.hour).strftime('%H:%M'))
        Notification::PushNotificationService.new(notification: notification.reload).perform
        expect(WebPush).to have_received(:payload_send).once
      end
    end

    it 'leaves other workspaces as they were' do
      with_modified_env(VAPID_PUBLIC_KEY: 'test') do
        now = Time.current.utc
        quiet((now - 1.hour).strftime('%H:%M'), (now + 1.hour).strftime('%H:%M'))
        Notification::PushNotificationService.new(notification: notification).perform
        expect(WebPush).to have_received(:payload_send).with(hash_including(message: include(notification.push_message_title)))
      end
    end
  end
end
