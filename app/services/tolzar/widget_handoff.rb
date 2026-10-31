# Tolzar own widget: "continue on WhatsApp / Instagram / Telegram" links per website inbox (round 3 c51). Plain deep
# links (wa.me, ig.me, t.me), no Meta API: they open the visitor's own app on the business's number or account.
# Stored in account.settings['tolzar_widget_handoff'][inbox_id]; set by the workspace owner; shown by the Tolzar
# widget only (TOLZAR_OWN_WIDGET_ACCOUNTS).
module Tolzar::WidgetHandoff
  KEY = 'tolzar_widget_handoff'.freeze
  FORMATS = {
    'whatsapp' => /\A\+[1-9]\d{6,14}\z/,
    'instagram' => /\A[A-Za-z0-9._]{1,30}\z/,
    'telegram' => /\A[A-Za-z][A-Za-z0-9_]{4,31}\z/
  }.freeze

  module_function

  def for_inbox(inbox)
    raw = ((inbox.account.settings || {})[KEY] || {})[inbox.id.to_s]
    raw.is_a?(Hash) ? raw.slice(*FORMATS.keys) : {}
  end

  # [{channel:, url:}] for the widget; only valid entries.
  def links(inbox)
    for_inbox(inbox).filter_map do |channel, value|
      next unless value.to_s.match?(FORMATS[channel])

      { channel: channel, url: url(channel, value.to_s) }
    end
  end

  def url(channel, value)
    case channel
    when 'whatsapp' then "https://wa.me/#{value.delete('+')}"
    when 'instagram' then "https://ig.me/m/#{value}"
    when 'telegram' then "https://t.me/#{value}"
    end
  end

  # => [values, errors]
  def validate(params)
    values = {}
    errors = []
    FORMATS.each do |channel, format|
      value = params[channel].to_s.strip.delete_prefix('@').gsub(/[\s-]/, '')
      next if value.blank?

      value.match?(format) ? values[channel] = value : errors << "#{channel}: not a valid #{channel == 'whatsapp' ? '+number' : 'handle'}"
    end
    [values, errors]
  end

  def save!(inbox, values)
    account = inbox.account
    all = ((account.settings || {})[KEY] || {}).merge(inbox.id.to_s => values)
    account.update!(settings: (account.settings || {}).merge(KEY => all))
  end
end
