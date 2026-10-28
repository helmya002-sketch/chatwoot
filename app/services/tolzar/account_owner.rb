# Tolzar (H3): the account owner, the one member who is always a Tolzar Owner and can never be
# demoted or removed. Stored as internal_attributes['tolzar_owner_user_id'] (not writable through the
# account API; only Super Admin / the console can move it). When it is not set yet (or that user left the
# account through Super Admin), the account's first administrator by membership date becomes the
# owner and is stored, so it never changes again on its own.
module Tolzar::AccountOwner
  KEY = 'tolzar_owner_user_id'.freeze

  module_function

  def user_id(account)
    stored = account.internal_attributes[KEY].to_i
    return stored if stored.positive? && account.account_users.exists?(user_id: stored)

    first = account.account_users.administrator.order(:created_at, :id).first&.user_id
    return if first.nil?

    account.update!(internal_attributes: account.internal_attributes.merge(KEY => first))
    first
  end

  def owner?(account, user)
    user.present? && user_id(account) == user.id
  end
end
