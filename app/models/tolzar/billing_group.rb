# Tolzar: a billing group (Business plan): up to MAX_MEMBERS workspaces share one monthly AI-reply
# allowance. The brain is the source of truth for the members, the allowance, the timezone and the
# counters (brain plugins/billing_groups.py, same group id as brain_group_id); this row keeps the fork's
# side: the Owner who created it, the plan, and the provider-neutral subscription reference that
# billing v1 fills in (provider, customer_ref, subscription_ref: empty until then). Member workspaces
# point here through accounts.tolzar_billing_group_id. Generic: nothing here is tied to one business.
class Tolzar::BillingGroup < ApplicationRecord
  self.table_name = 'tolzar_billing_groups'

  MAX_MEMBERS = 5

  validates :brain_group_id, presence: true, uniqueness: true
  validates :plan, presence: true

  def member_accounts
    Account.where(tolzar_billing_group_id: id)
  end

  # Points exactly these workspaces at this group (and no others).
  def assign_members!(account_ids)
    ids = Array(account_ids).map(&:to_i)
    member_accounts.where.not(id: ids).update_all(tolzar_billing_group_id: nil) # rubocop:disable Rails/SkipsModelValidations
    Account.where(id: ids).update_all(tolzar_billing_group_id: id) # rubocop:disable Rails/SkipsModelValidations
  end

  def release_members!
    member_accounts.update_all(tolzar_billing_group_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
