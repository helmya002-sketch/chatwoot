# frozen_string_literal: true

# Tolzar: in this deployment every email address is rejected (even gmail.com) —
# agent invites fail ("Email is not an email") and contact emails fail ("Invalid
# email"). That blocks onboarding any real teammate. We relax email validation to
# a standard `addr@domain.tld` format check.
#
# Earlier attempts in `after_initialize` were too late (the validators had already
# captured the strict regexp at model load). Instead, in `to_prepare` (runs after
# models load on every boot/reload) we MUTATE the existing validator instances:
#   * format validators on :email -> swap their regexp for a permissive one
#   * valid_email2's EmailValidator -> redefine to the same permissive check
# (no MX / disposable / strict-parse lookups, which fail in this container).

TOLZAR_EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

# Belt-and-suspenders: also set the Devise regexp at load time.
Devise.email_regexp = TOLZAR_EMAIL_REGEXP if defined?(Devise)

Rails.application.config.to_prepare do
  Devise.email_regexp = TOLZAR_EMAIL_REGEXP if defined?(Devise)

  models = []
  models << User if defined?(User)
  models << Contact if defined?(Contact)

  models.each do |klass|
    next unless klass.respond_to?(:_validators)

    Array(klass._validators[:email]).each do |validator|
      next unless validator.is_a?(ActiveModel::Validations::FormatValidator)
      next unless validator.options[:with].is_a?(Regexp)

      # validator.options is FROZEN — build a fresh unfrozen hash and swap the
      # reference (the callback chain holds this same instance, so this takes
      # effect without re-registering the validation).
      new_opts = validator.options.dup
      new_opts[:with] = TOLZAR_EMAIL_REGEXP
      validator.instance_variable_set(:@options, new_opts)
    end
  end

  if defined?(EmailValidator)
    EmailValidator.class_eval do
      def validate_each(record, attribute, value)
        return if value.blank?

        Array(value).each do |entry|
          next if entry.to_s.match?(TOLZAR_EMAIL_REGEXP)

          record.errors.add(attribute, options[:message] || :invalid)
        end
      end
    end
  end
end
