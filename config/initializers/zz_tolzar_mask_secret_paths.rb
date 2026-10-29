# frozen_string_literal: true

# Tolzar: a workspace Meta app's webhook URL carries its secret token in the path
# (/tolzar/meta/hook/<32 hex>). filter_parameters masks it in the params, but Rails' "Started POST
# <path>" line (and lograge's path, when enabled) would print it. Both are masked here.
module TolzarMaskedPathLog
  SECRET_PATHS = %r{(/tolzar/meta/hook/)\h{32}}

  def self.mask(text)
    text.to_s.gsub(SECRET_PATHS, '\1[FILTERED]')
  end

  private

  def started_request_message(request)
    TolzarMaskedPathLog.mask(super)
  end
end

Rails::Rack::Logger.prepend(TolzarMaskedPathLog) unless Rails::Rack::Logger.ancestors.include?(TolzarMaskedPathLog)

if Rails.application.config.respond_to?(:lograge) && Rails.application.config.lograge.enabled
  previous = Rails.application.config.lograge.custom_options
  Rails.application.config.lograge.custom_options = lambda do |event|
    extra = previous.respond_to?(:call) ? previous.call(event) : {}
    extra.merge(path: TolzarMaskedPathLog.mask(event.payload[:path]))
  end
end
