require 'rails_helper'

# Deliverability (Oracle, 30 Oct): HTML-only app mail gets a text/plain part with the same content.
RSpec.describe Tolzar::PlainTextPart do
  let(:html) do
    '<html><head><style>p{}</style></head><body><h1>Reset your password</h1><p>Hello Mona,</p>' \
      '<p><a href="https://app.example.com/app/auth/password/edit?reset_password_token=abc">Change my password</a></p>' \
      '<p>Line one<br>Line two</p><ul><li>First</li><li>Second</li></ul></body></html>'
  end

  it 'turns a single-part HTML mail into text + HTML with the same content' do
    message = Mail.new(to: 'a@example.com', from: 'b@example.com', subject: 'x', content_type: 'text/html; charset=UTF-8', body: html)
    described_class.delivering_email(message)

    expect(message.mime_type).to eq('multipart/alternative')
    expect(message.html_part.body.decoded).to eq(html)
    text = message.text_part.body.decoded
    expect(text).to include('Reset your password', 'Hello Mona,', 'Line one', 'Line two', '- First', '- Second')
    expect(text).to include('Change my password (https://app.example.com/app/auth/password/edit?reset_password_token=abc)')
    expect(text).not_to include('<', 'p{}')
  end

  it 'leaves multipart and plain-text mail alone' do
    plain = Mail.new(to: 'a@example.com', from: 'b@example.com', subject: 'x', body: 'Hi')
    described_class.delivering_email(plain)
    expect(plain.multipart?).to be(false)
    expect(plain.body.decoded).to eq('Hi')
  end

  it 'is applied to real app mail (Devise password reset)' do
    user = create(:user)
    perform_enqueued_jobs { user.send_reset_password_instructions }
    mail = ActionMailer::Base.deliveries.last
    expect(mail.text_part).to be_present
    expect(mail.html_part).to be_present
    expect(mail.text_part.body.decoded).to include('reset_password_token=')
  end
end
