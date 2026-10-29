# Tolzar: a workspace's own Meta app (one per workspace), for Facebook Messenger, Instagram DMs and
# comments. The business creates it in its own Meta Business portfolio and the workspace Owner pastes
# the app id and secret (Settings > Channels > Meta app). Meta calls this app's own webhook,
# /tolzar/meta/hook/<webhook_token>, verified with this app's secret (Tolzar::MetaHookController).
# The secret and the verify token are encrypted and never returned; the webhook token names neither
# the workspace nor the app. Generic: nothing here is tied to one business.
class Tolzar::MetaApp < ApplicationRecord
  self.table_name = 'tolzar_meta_apps'

  belongs_to :account

  if Chatwoot.encryption_configured?
    encrypts :app_secret
    encrypts :verify_token
  end

  validates :account_id, uniqueness: true
  validates :app_id, format: { with: /\A\d{10,20}\z/, message: 'is the numeric App ID from the Meta app dashboard' }
  validates :app_secret, format: { with: /\A\h{32}\z/, message: 'is the 32-character App secret' }
  validates :webhook_token, presence: true, uniqueness: true

  before_validation :ensure_tokens, on: :create

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/tolzar/meta/hook/#{webhook_token}"
  end

  # Meta signs every webhook POST with the app secret: X-Hub-Signature-256: sha256=<hex>.
  def valid_signature?(raw_body, header)
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, raw_body.to_s)}"
    header.present? && ActiveSupport::SecurityUtils.secure_compare(expected, header.to_s)
  end

  def valid_verify_token?(token)
    token.present? && ActiveSupport::SecurityUtils.secure_compare(verify_token.to_s, token.to_s)
  end

  # What the settings page may show: never the secret or the verify token.
  def view
    { app_id: app_id, webhook_url: webhook_url, secret_last4: app_secret.to_s.last(4), created_at: created_at }
  end

  private

  def ensure_tokens
    self.webhook_token ||= SecureRandom.hex(16)
    self.verify_token ||= SecureRandom.hex(16)
  end
end
