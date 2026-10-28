# frozen_string_literal: true

# Tolzar (roadmap A6): an audit log of what admins change, without enterprise/.
# Chatwoot's core already bundles the `audited` gem (MIT) and the `audits` table; only the
# models' audit declarations and the audit class live in enterprise/, which the Tolzar image
# no longer ships (A4). So when enterprise/ is absent, audit the same core models here with
# the gem's own Audited::Audit class. Secrets are filtered out of what is recorded.
unless ChatwootApp.enterprise?
  Audited.config { |config| config.audit_class = 'Audited::Audit' }

  Rails.application.config.to_prepare do
    secret = %w[password encrypted_password access_token token secret api_key webhook_secret
                hmac_token reset_password_token confirmation_token tokens otp_secret].freeze

    {
      'Account' => { except: %w[updated_at] + secret, on: [:update] },
      'AccountUser' => { only: %w[availability role account_id inviter_id user_id], on: [:create, :update, :destroy],
                         associated_with: :account },
      'Inbox' => { except: %w[updated_at] + secret, on: [:create, :update, :destroy], associated_with: :account },
      'Team' => { except: %w[updated_at], on: [:create, :update, :destroy], associated_with: :account },
      'AutomationRule' => { except: %w[updated_at], on: [:create, :update, :destroy], associated_with: :account },
      'Macro' => { except: %w[updated_at], on: [:create, :update, :destroy], associated_with: :account },
      'Webhook' => { except: %w[updated_at] + secret, on: [:create, :update, :destroy], associated_with: :account },
      'CustomAttributeDefinition' => { except: %w[updated_at], on: [:create, :update, :destroy], associated_with: :account }
    }.each do |name, opts|
      klass = name.safe_constantize
      next if klass.nil? || klass.respond_to?(:audited_options)

      klass.audited(**opts)
    end
    Account.has_associated_audits unless Account.reflect_on_association(:associated_audits)
  end
end
