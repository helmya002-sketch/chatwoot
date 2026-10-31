# Tolzar conversation transcript (round 4, H1): GET tolzar/conversations/:display_id/transcript, a print-friendly HTML
# page of one conversation (times, sender names, text; attachments as file names). Private notes only with
# notes=1. Anyone who can see the conversation (ConversationPolicy#show?); TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces
# (404 otherwise). The browser's print saves it as PDF; nothing is stored or sent.
class Api::V1::Accounts::TolzarTranscriptController < Api::V1::Accounts::BaseController
  LIMIT = 5000

  def show
    return head(:not_found) unless Tolzar::CannedStarters.enabled?(Current.account.id)

    conversation = Current.account.conversations.find_by!(display_id: params[:display_id])
    authorize conversation, :show?
    notes = ActiveModel::Type::Boolean.new.cast(params[:notes]) == true
    render template: 'tolzar/transcripts/show', formats: [:html], layout: false, content_type: 'text/html',
           locals: { conversation: conversation, rows: rows(conversation, notes), notes: notes, zone: zone }
  end

  private

  def rows(conversation, notes)
    scope = conversation.messages.where(message_type: %i[incoming outgoing activity]).includes(:sender, attachments: { file_attachment: :blob })
    scope = scope.where(private: false) unless notes
    scope.reorder(:created_at, :id).limit(LIMIT).map do |message|
      { at: message.created_at.in_time_zone(zone), kind: kind(message), sender: sender_name(message),
        text: message.content.to_s, files: message.attachments.map { |a| file_name(a) } }
    end
  end

  def kind(message)
    return 'note' if message.private?

    message.message_type
  end

  def sender_name(message)
    return '' if message.activity?

    sender = message.sender
    sender.respond_to?(:available_name) ? sender.available_name : sender&.name.presence || I18n.t('tolzar.transcript.system')
  end

  def file_name(attachment)
    return attachment.file.filename.to_s if attachment.file.attached?

    attachment.file_type.to_s
  end

  # The viewer's own time zone when the browser sends a valid one; UTC otherwise.
  def zone
    @zone ||= ActiveSupport::TimeZone[params[:tz].to_s] || ActiveSupport::TimeZone['UTC']
  end
end
