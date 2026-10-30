# Tolzar: the Business plan's pooled AI-reply allowance (docs/reports/TOLZAR-POOLED-ALLOWANCE-PLAN-2026-10-30.md).
# A billing group shares one monthly allowance of AI replies between up to 5 workspaces. The brain stores
# the members, the allowance, the timezone and the counters and runs the pooled gate
# (plugins/billing_groups.py); it lets a workspace create only a group that includes itself and change
# only its own group. The rule it leaves to us is enforced here, BEFORE the brain is called: only a user
# who is an Owner of EVERY member workspace (the old members and the new ones) may create, change or
# delete a group, its allowance or its members. Anyone else gets 403. Every change is audited on each
# workspace it touches (Chatwoot's audit table, shown in Settings > Audit log; the brain audits too).
#
# What counts as an AI reply (decision of 30 Oct): a message the AI writes and sends to a customer in a
# live channel. Notes in observation (shadow) mode, the AI-Agents test chat and quality checks are not
# counted. The per-workspace quotas stay the compute bound and are shown read-only on the same page.
module TolzarBillingGroupActions
  extend ActiveSupport::Concern

  BILLING_ACTIONS = %i[billing_group billing_group_save billing_group_delete].freeze
  BILLING_TZ = %r{\A[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}\z}
  # Bounds the brain role lookups for the "workspaces you can add" list.
  BILLING_CANDIDATES_MAX = 50

  included do
    before_action :ensure_billing_admin, only: BILLING_ACTIONS
  end

  # Every administrator of this workspace (Owner or Manager) sees the group, its meter and the caps.
  def billing_group
    res = brain_billing_group
    return render_brain(res) if billing_brain_failed?(res)

    render json: billing_group_view(res)
  end

  # Creates the group (no group yet) or changes this workspace's group: members, allowance, tz, on/off.
  def billing_group_save
    current = brain_billing_group
    return render_brain(current) if billing_brain_failed?(current)

    old = current['group']
    old_members = billing_ids(old)
    members = billing_member_ids
    return billing_refusal('invalid_settings', :bad_request) if members.nil? || members.empty?
    return billing_refusal('too_many_members', :unprocessable_entity) if members.size > Tolzar::BillingGroup::MAX_MEMBERS
    return billing_refusal('must_include_this_workspace', :unprocessable_entity) if old.nil? && members.exclude?(account_scope_id)

    limit = billing_limit
    tz = billing_tz(old)
    return billing_refusal('invalid_settings', :bad_request) if limit == :invalid || tz.nil?
    return billing_refusal('owner_only', :forbidden) unless owner_of_every?(members | old_members)

    record = old && Tolzar::BillingGroup.find_by(brain_group_id: old['id'])
    taken = Account.where(id: members).where.not(tolzar_billing_group_id: nil)
    taken = taken.where.not(tolzar_billing_group_id: record.id) if record
    return billing_refusal('in_another_group', :conflict) if taken.exists?

    body = { account_id: account_scope_id, members: members, monthly_ai_replies: limit, tz: tz,
             enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]) || false }
    body[:id] = old['id'] if old
    res = post_to_brain('/billing_groups', body)
    return render_brain(res) unless res.is_a?(Hash) && res['ok'] == true

    gid = res.dig('group', 'id') || old&.dig('id')
    record = Tolzar::BillingGroup.find_or_initialize_by(brain_group_id: gid)
    record.owner_user_id ||= Current.user.id
    record.save!
    record.assign_members!(members)
    billing_audit!(members | old_members, old, body.except(:account_id).merge(id: gid))
    render json: billing_group_view(res)
  end

  def billing_group_delete
    current = brain_billing_group
    return render_brain(current) if billing_brain_failed?(current)

    old = current['group']
    return billing_refusal('not_found', :not_found) if old.nil?

    members = billing_ids(old)
    return billing_refusal('owner_only', :forbidden) unless owner_of_every?(members)

    res = post_to_brain('/billing_groups/delete', { account_id: account_scope_id, id: old['id'] })
    return render_brain(res) unless res.is_a?(Hash) && res['ok'] == true

    record = Tolzar::BillingGroup.find_by(brain_group_id: old['id'])
    if record
      record.release_members!
      record.destroy!
    end
    billing_audit!(members, old, nil)
    render json: billing_group_view(res)
  end

  private

  def ensure_billing_admin
    return if Current.account_user&.administrator?

    render json: { ok: false, error: 'owner_only' }, status: :forbidden
  end

  def brain_billing_group
    get_from_brain("/billing_groups?account_id=#{account_scope_id}")
  end

  def billing_brain_failed?(res)
    !res.is_a?(Hash) || res['ok'] == false || (res.key?('detail') && !res.key?('ok'))
  end

  def billing_refusal(error, status)
    render json: { ok: false, error: error }, status: status
  end

  def billing_ids(group)
    group.is_a?(Hash) ? Array(group['members']).map(&:to_i) : []
  end

  # nil when a member is not a whole positive id.
  def billing_member_ids
    ids = Array(params[:members]).map { |m| Integer(m.to_s, exception: false) }
    return nil if ids.any? { |i| i.nil? || !i.positive? }

    ids.uniq
  end

  # Empty = no ceiling; otherwise a positive whole number.
  def billing_limit
    raw = params[:monthly_ai_replies].to_s.strip
    return nil if raw.empty?

    n = Integer(raw, exception: false)
    n&.positive? ? n : :invalid
  end

  # Kept when not sent; the brain checks it is a real timezone.
  def billing_tz(old)
    raw = params[:tz].to_s.strip
    raw = (old && old['tz']).presence || 'UTC' if raw.empty?
    raw.size <= 64 && raw.match?(BILLING_TZ) ? raw : nil
  end

  def owner_of_every?(ids)
    accounts = Account.where(id: ids).index_by(&:id)
    ids.all? { |id| tolzar_owner_of?(accounts[id]) }
  end

  # The same Owner rule as #owner? (H3), for any workspace the signed-in user belongs to. For another
  # workspace the brain's role table is read signed for THAT workspace, and only after Rails has checked
  # the user is an administrator there.
  def tolzar_owner_of?(account)
    return false if account.nil?
    return owner? if account.id == account_scope_id

    @tolzar_owner_of ||= {}
    return @tolzar_owner_of[account.id] if @tolzar_owner_of.key?(account.id)

    @tolzar_owner_of[account.id] = billing_owner_check(account)
  end

  def billing_owner_check(account)
    member = account.account_users.find_by(user_id: Current.user.id)
    return false unless member&.administrator?

    owner_id = Tolzar::AccountOwner.user_id(account)
    return true if owner_id == Current.user.id

    table = get_from_brain_as(account.id, "/roles?account_id=#{account.id}&owner_user_id=#{owner_id}")['roles']
    table.is_a?(Hash) && table[Current.user.id.to_s] == 'owner'
  end

  def billing_snapshot(group)
    return nil unless group.is_a?(Hash)

    group.stringify_keys.slice('id', 'members', 'monthly_ai_replies', 'tz', 'enabled')
  end

  def billing_audit!(account_ids, before, after)
    Account.where(id: account_ids).find_each do |account|
      Audited::Audit.create!(auditable: account, associated: account, user: Current.user, action: 'update',
                             audited_changes: { 'tolzar_billing_group' => [billing_snapshot(before), billing_snapshot(after)] },
                             comment: 'Tolzar billing group')
    end
  end

  # The page's data: the brain's pooled meter plus, per member, its name (only for workspaces the user
  # belongs to), its AI replies this month and its own caps (read-only, for workspaces the user
  # administers); whether the user may manage the group, and which of their workspaces they may add.
  def billing_group_view(res)
    group = res['group']
    ids = billing_ids(group)
    record = group && Tolzar::BillingGroup.find_by(brain_group_id: group['id'])
    mine = Current.user.account_users.where(account_id: ids).index_by(&:account_id)
    names = Account.where(id: mine.keys).pluck(:id, :name).to_h
    by_member = res['used_by_member'].is_a?(Hash) ? res['used_by_member'] : {}
    can_manage = group ? owner_of_every?(ids) : owner?
    { ok: true, switch_on: res['switch_on'] == true,
      group: group && billing_snapshot(group).merge('plan' => record&.plan || 'business'),
      used: res['used'], remaining: res['remaining'], period: res['period'],
      counting_since: res['counting_since'],
      members: ids.map do |id|
        { id: id, name: names[id], current: id == account_scope_id, used: by_member[id.to_s].to_i,
          caps: mine[id]&.administrator? ? billing_caps(id) : nil }
      end,
      can_manage: can_manage, max_members: Tolzar::BillingGroup::MAX_MEMBERS,
      candidates: can_manage ? billing_candidates(record, ids) : [] }
  end

  def billing_caps(account_id)
    res = get_from_brain_as(account_id, "/quotas?account_id=#{account_id}")
    quota = res.is_a?(Hash) ? res['quota'] : nil
    return nil unless quota.is_a?(Hash)

    { daily_calls: quota['daily_calls'], monthly_tokens: quota['monthly_tokens'] }
  end

  # The user's own workspaces (Owner there) that are in no other group.
  def billing_candidates(record, ids)
    scope = Account.joins(:account_users).where(account_users: { user_id: Current.user.id, role: AccountUser.roles[:administrator] })
    scope = scope.where(tolzar_billing_group_id: [nil, record&.id].uniq)
    scope.where.not(id: ids).order(:id).limit(BILLING_CANDIDATES_MAX).select { |a| tolzar_owner_of?(a) }
         .map { |a| { id: a.id, name: a.name } }
  end
end
