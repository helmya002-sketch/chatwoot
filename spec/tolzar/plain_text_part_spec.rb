require 'rails_helper'

# Deliverability (Oracle, 30 Oct): the app's own HTML-only mail gets a text/plain part with the same content.
# Customer-facing conversation replies are never changed.
RSpec.describe Tolzar::PlainTextPart do
  let(:html) do
    '<html><head><style>p{}</style></head><body><h1>Reset your password</h1><p>Hello Mona,</p>' \
      '<p><a href="https://app.example.com/app/auth/password/edit?reset_password_token=abc">Change my password</a></p>' \
      '<p>Line one<br>Line two</p><ul><li>First</li><li>Second</li></ul></body></html>'
  end

  def html_mail(handler)
    Mail.new(to: 'a@example.com', from: 'b@example.com', subject: 'x', content_type: 'text/html; charset=UTF-8', body: html)
        .tap { |m| m.delivery_handler = handler }
  end

  it "turns the app's single-part HTML mail into text + HTML with the same content" do
    message = html_mail(Devise::Mailer)
    described_class.delivering_email(message)

    expect(message.mime_type).to eq('multipart/alternative')
    expect(message.html_part.body.decoded).to eq(html)
    text = message.text_part.body.decoded
    expect(text).to include('Reset your password', 'Hello Mona,', 'Line one', 'Line two', '- First', '- Second')
    expect(text).to include('Change my password (https://app.example.com/app/auth/password/edit?reset_password_token=abc)')
    expect(text).not_to include('<', 'p{}')
  end

  it 'covers the administrator notifications (subclasses included)' do
    message = html_mail(AdministratorNotifications::ChannelNotificationsMailer)
    described_class.delivering_email(message)
    expect(message.mime_type).to eq('multipart/alternative')
  end

  it 'never changes a customer-facing conversation reply, other mailers or plain-text mail' do
    reply = html_mail(ConversationReplyMailer)
    described_class.delivering_email(reply)
    expect(reply.multipart?).to be(false)
    expect(reply.body.decoded).to eq(html)

    plain = Mail.new(to: 'a@example.com', from: 'b@example.com', subject: 'x', body: 'Hi').tap { |m| m.delivery_handler = Devise::Mailer }
    described_class.delivering_email(plain)
    expect(plain.multipart?).to be(false)
  end

  it 'records the mailer on a real Devise message' do
    message = Devise::Mailer.reset_password_instructions(create(:user), 'tok').message
    expect(described_class.app_mail?(message)).to be(true)
  end
end
