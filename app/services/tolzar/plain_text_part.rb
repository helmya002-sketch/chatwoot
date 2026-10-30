# Tolzar deliverability (Oracle, 30 Oct): HTML-only mail scores worse with Gmail. Right before delivery, the
# app's OWN single-part text/html mail to its users (Devise's confirmation, reset, unlock and invitation mails; the
# administrator notifications, fair use included; the agent notifications) becomes multipart/alternative: a text/plain part with the same content, then
# the original HTML. Links keep their address ("Change my password (https://…)"). Customer-facing conversation
# replies (ConversationReplyMailer) and every other mailer are left exactly as they are, as is mail that is
# already multipart. Registered in config/initializers/zz_tolzar_plain_text_part.rb.
class Tolzar::PlainTextPart
  BLOCKS = %w[p div h1 h2 h3 h4 h5 h6 tr table ul ol blockquote].freeze
  MAILERS = %w[Devise::Mailer AdministratorNotifications::BaseMailer AgentNotifications::ConversationNotificationsMailer].freeze

  def self.delivering_email(message)
    return unless app_mail?(message)
    return if message.multipart? || message.mime_type != 'text/html'

    html = message.body.decoded
    charset = message.charset.presence || 'UTF-8'
    text = to_text(html)
    message.body = nil
    message.content_type = nil
    message.content_transfer_encoding = nil
    message.text_part = Mail::Part.new(content_type: "text/plain; charset=#{charset}", body: text)
    message.html_part = Mail::Part.new(content_type: "text/html; charset=#{charset}", body: html)
  end

  # Only mail built by one of MAILERS (or a subclass); ActionMailer records the mailer as the delivery handler.
  def self.app_mail?(message)
    handler = message.delivery_handler
    return false unless handler.is_a?(Class)

    MAILERS.any? { |name| (klass = name.safe_constantize) && handler <= klass }
  end

  def self.to_text(html)
    doc = Nokogiri::HTML(html.to_s)
    doc.css('script, style, head, title').remove
    doc.css('a[href]').each do |a|
      href = a['href'].to_s.strip
      label = a.text.squish
      a.replace(label.blank? || label == href || href.start_with?('#') ? (label.presence || href) : "#{label} (#{href})")
    end
    doc.css('br').each { |br| br.replace("\n") }
    doc.css('li').each { |li| li.add_previous_sibling("\n- ") }
    doc.css(BLOCKS.join(', ')).each { |node| node.add_next_sibling("\n\n") }
    doc.text.gsub(/[ \t ]+/, ' ').gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
