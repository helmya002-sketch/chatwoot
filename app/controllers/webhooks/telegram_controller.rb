class Webhooks::TelegramController < ActionController::API
  # M5 (full-sec): an update for a known bot must carry the secret_token registered with setWebhook.
  # A channel set up before this change gets it on its next save (setup_telegram_webhook runs on save).
  before_action :verify_secret_token!

  def process_payload
    Webhooks::TelegramEventsJob.perform_later(params.to_unsafe_hash)

    callback_query = params[:callback_query]
    callback_query_id = callback_query[:id] if callback_query.respond_to?(:key?)
    return head :ok unless callback_query_id.is_a?(String) && callback_query_id.present?

    render json: { method: 'answerCallbackQuery', callback_query_id: callback_query_id }
  end

  private

  def verify_secret_token!
    channel = Channel::Telegram.find_by(bot_token: params[:bot_token].to_s)
    return if channel.blank?
    return if Tolzar::WebhookToken.match?(channel.webhook_secret_token, request.headers['X-Telegram-Bot-Api-Secret-Token'])

    Rails.logger.warn("[TELEGRAM] rejected webhook with a missing or invalid secret token for channel #{channel.id}")
    head :forbidden
  end
end
