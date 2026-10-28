# frozen_string_literal: true

# LOW (full-sec): mirror errors can carry customer content (a respond.io payload value, a contact's
# name or phone in a validation message). Logs and the mirror_events.error column get the error class
# and a short code only: the first 8 hex chars of SHA-256(message), so the same failure groups
# together without the message itself ever reaching a log.
module Tolzar::Mirror::LogSafe
  module_function

  def code(error)
    Digest::SHA256.hexdigest(error.message.to_s)[0, 8]
  end

  def describe(error)
    "#{error.class} code=#{code(error)}"
  end
end
