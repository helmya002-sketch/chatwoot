require 'rails_helper'

# SRV-015: app mail gets a Message-ID on the sender's own domain instead of "<…@container.mail>"; a mailer's own
# Message-ID (conversation replies, for threading) is kept.
RSpec.describe Tolzar::MessageIdDomain do
  def mail(**attrs)
    Mail.new(from: 'Tolzar <noreply@tolzar.com>', to: 'a@example.com', subject: 's', body: 'b', **attrs)
  end

  it 'gives a mail without a Message-ID one on the sender domain' do
    with_modified_env(MAILER_SENDER_EMAIL: 'Tolzar <noreply@tolzar.com>') do
      m = mail
      described_class.delivering_email(m)
      expect(m.message_id).to match(/\A[0-9a-f-]{36}@tolzar\.com\z/)
    end
  end

  it 'keeps a Message-ID the mailer set (threading)' do
    m = mail(message_id: '<conversation/abc/messages/1@reply.example.com>')
    described_class.delivering_email(m)
    expect(m.message_id).to eq('conversation/abc/messages/1@reply.example.com')
  end

  it 'leaves the default when no real sender domain is known' do
    with_modified_env(MAILER_SENDER_EMAIL: 'Tolzar <noreply@tolzar.invalid>') do
      m = Mail.new(from: 'x@tolzar.invalid', to: 'a@example.com', body: 'b')
      described_class.delivering_email(m)
      expect(m.message_id).to be_nil
    end
  end
end
