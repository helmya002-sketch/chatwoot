# Tolzar audit log (A6), one page at a time: Chatwoot's audits for the workspace (ActiveRecord, filtered
# and counted in the database) merged with the brain's settings log (its newest BRAIN_LIMIT entries,
# filtered here), newest first. Filters: audit_action ("contact.update", "agent.save"; `action` is
# Rails' own route parameter), actor (a user id), from / to (ISO 8601 dates or times; a date-only `to`
# takes the whole day). Secret-looking fields never leave the server.
class Tolzar::AuditLogQuery
  MAX_PER_PAGE = 100
  DEFAULT_PER_PAGE = 50
  MAX_PAGE = 100
  BRAIN_LIMIT = 1000
  HIDDEN = /token|secret|password|otp|api_key|account_sid|credential/i
  DATE = /\A\d{4}-\d{2}-\d{2}\z/

  class Refused < StandardError; end

  def initialize(account:, params:)
    @account = account
    @page = number(params[:page], 'page', 1..MAX_PAGE) || 1
    @per_page = number(params[:per_page], 'per_page', 1..MAX_PER_PAGE) || DEFAULT_PER_PAGE
    @actor = number(params[:actor], 'actor', 1..)
    @audit_action = params[:audit_action].presence&.to_s
    @from = time(params[:from], 'from')
    @to = time(params[:to], 'to', end_of_day: true)
  end

  def perform(brain_entries)
    brain = brain_entries.filter_map { |entry| brain_entry(entry) }.select { |entry| keep?(entry) }
    rows = chatwoot_scope.order(created_at: :desc, id: :desc).limit(@page * @per_page).to_a
    users = User.where(id: rows.filter_map(&:user_id).uniq).index_by(&:id)
    chatwoot = rows.map { |row| chatwoot_entry(row, users) }
    entries = (chatwoot + brain).sort_by { |entry| -entry[:at].to_f }.slice((@page - 1) * @per_page, @per_page) || []
    { entries: entries, total: chatwoot_scope.count + brain.size, page: @page, per_page: @per_page }
  end

  private

  def chatwoot_scope
    scope = Audited::Audit.where(associated_type: 'Account', associated_id: @account.id)
                          .or(Audited::Audit.where(auditable_type: 'Account', auditable_id: @account.id))
    scope = scope.where(user_id: @actor) if @actor
    scope = scope.where(created_at: @from..) if @from
    scope = scope.where(created_at: ..@to) if @to
    return scope unless @audit_action

    type, action = @audit_action.split('.', 2)
    action.present? ? scope.where(auditable_type: type.camelize, action: action) : scope.none
  end

  def chatwoot_entry(row, users)
    { source: 'chatwoot', at: row.created_at, action: "#{row.auditable_type.underscore}.#{row.action}",
      target: "#{row.auditable_type} #{row.auditable_id}", actor_id: row.user_id,
      actor: users[row.user_id]&.email || row.username || 'system',
      changes: (row.audited_changes || {}).reject { |key, _| key.to_s.match?(HIDDEN) } }
  end

  # The brain names the actor "<user id>:<email>" (TolzarController#actor_label).
  def brain_entry(entry)
    at = Time.zone.parse(entry['at'].to_s)
    return if at.nil?

    actor_id = Integer(entry['actor'].to_s.split(':', 2).first, exception: false)
    { source: 'brain', at: at, action: entry['action'], target: entry['target'], actor_id: actor_id,
      actor: entry['actor'], changes: entry['changes'] }
  end

  def keep?(entry)
    return false if @actor && entry[:actor_id] != @actor
    return false if @audit_action && entry[:action] != @audit_action
    return false if @from && entry[:at] < @from

    !(@to && entry[:at] > @to)
  end

  def number(value, name, range)
    return if value.blank?

    n = Integer(value.to_s, exception: false)
    raise Refused, "#{name}: a whole number in #{range}" unless n && range.cover?(n)

    n
  end

  def time(value, name, end_of_day: false)
    return if value.blank?

    text = value.to_s
    return Time.iso8601(text) unless text.match?(DATE)

    day = Date.iso8601(text).in_time_zone
    end_of_day ? day.end_of_day : day
  rescue ArgumentError
    raise Refused, "#{name}: an ISO 8601 date or time"
  end
end
