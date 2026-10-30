# Tolzar deliverability (Oracle, 30 Oct): HTML-only mail scores worse with Gmail. Right before delivery, every
# single-part text/html message (Devise's confirmation, reset and invitation mails, the liquid notification
# mailers) becomes multipart/alternative: a text/plain part with the same content, then the original HTML.
# Links keep their address ("Change my password (https://…)"). Mail that is already multipart (attachments,
# the newsletter) is left as it is. Registered in config/initializers/zz_tolzar_plain_text_part.rb.
class Tolzar::PlainTextPart
  BLOCKS = %w[p div h1 h2 h3 h4 h5 h6 tr table ul ol blockquote].freeze

  def self.delivering_email(message)
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
