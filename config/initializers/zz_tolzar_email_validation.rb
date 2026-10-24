# frozen_string_literal: true

# Tolzar: in this deployment, email validation rejects EVERY address (even
# gmail.com) — agent invites fail ("Email is not an email") and contact emails
# fail ("Invalid email"). That blocks onboarding any real teammate, so we relax
# both validators to a standard `addr@domain.tld` format check:
#
#   * Contact uses `format: { with: Devise.email_regexp }` — re-assert a standard
#     permissive regexp (something resets it at runtime to one that rejects all).
#   * User (devise_token_auth) uses `email: true` -> valid_email2's top-level
#     EmailValidator, whose strict/MX/parse check fails here — override it to the
#     same standard format check (no MX/disposable lookup).

STANDARD_EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

Rails.application.config.after_initialize do
  Devise.email_regexp = STANDARD_EMAIL_REGEXP
end

Rails.application.config.to_prepare do
  if defined?(EmailValidator)
    EmailValidator.class_eval do
      def validate_each(record, attribute, value)
        return if value.blank?

        Array(value).each do |entry|
          next if entry.to_s.match?(STANDARD_EMAIL_REGEXP)

          record.errors.add(attribute, options[:message] || :invalid)
        end
      end
    end
  end
end
