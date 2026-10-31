# Tolzar booking documents: a staff member sends an issued document into its conversation. The brain renders the
# PDF (POST /documents/render: totals re-checked, no placeholder, no network); the PDF goes out as an attachment on
# a normal outgoing message from that staff member, on the conversation's own channel. Never by the AI: this runs
# only from the Send button. Drafts and cancelled documents are refused.
class Tolzar::DocumentSend
  Refused = Class.new(StandardError)

  def initialize(document:, user:)
    @document = document
    @user = user
  end

  def perform
    raise Refused, 'only an issued document can be sent' unless @document.status == 'issued'

    conversation = @document.conversation
    raise Refused, 'this document is not linked to a conversation' if conversation.nil?

    pdf = render
    message = conversation.messages.new(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                        message_type: :outgoing, sender: @user, content: caption)
    message.attachments.new(account_id: conversation.account_id, file_type: :file,
                            file: { io: StringIO.new(pdf), filename: "#{@document.number}.pdf", content_type: 'application/pdf' })
    message.save!
    @document.update!(history: Array(@document.history) + [{ 'action' => 'sent', 'by' => @user.id, 'at' => Time.current.utc.iso8601,
                                                             'version' => @document.version, 'message_id' => message.id }])
    message
  end

  private

  def render
    res = Tolzar::BrainClient.post('/documents/render', { document: @document.view, branding: branding },
                                   account_id: @document.account_id)
    case res['status']
    when 200 then Base64.strict_decode64(res['pdf_b64'].to_s)
    when 422 then raise Refused, "the document cannot be rendered (#{res['error']})"
    else raise Refused, 'the PDF renderer is not available right now'
    end
  end

  # The workspace's template (Tolzar::DocumentBranding). The renderer uses name, address, colour and terms; the
  # logo and title go along for the renderer's next round.
  def branding
    Tolzar::DocumentBranding.for_render(@document.account, @document.doc_type)
  end

  def caption
    titles = { 'voucher' => 'Voucher', 'quote' => 'Quote', 'confirmation' => 'Booking confirmation',
               'payment_summary' => 'Payment summary' }
    "#{titles[@document.doc_type]} #{@document.number}"
  end
end
