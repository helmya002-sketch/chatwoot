# Tolzar Control Center: the super-admin audit log (Tolzar::SuperAdminAudit), newest first, searchable by e-mail,
# path, action or note, filtered by date (from / to, UTC days) and by kind (sign-ins only = the super-admin sign-in
# history). The same filters export as CSV (note included; cells that would run as a formula start with a quote).
# Read-only: rows are never edited or deleted from the web.
class SuperAdmin::TolzarAuditsController < SuperAdmin::ApplicationController
  PER_PAGE = 100

  EXPORT_LIMIT = 10_000

  SIGN_INS = %w[sign_in sign_in_failed].freeze

  def show
    read_filters
    scope = filtered
    @page = [params[:page].to_i, 1].max
    @audits = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @audits.size > PER_PAGE
    @audits = @audits.first(PER_PAGE)
  end

  # The same search as CSV (newest first, at most EXPORT_LIMIT rows); field names only, as stored.
  def export
    read_filters
    csv = CSV.generate do |out|
      out << %w[at email method controller action path record fields status ip note]
      filtered.limit(EXPORT_LIMIT).each do |a|
        out << [a.created_at.utc.iso8601, a.email, a.http_method, a.controller, a.action, a.path, a.record_id,
                Array(a.fields).join(' '), a.status, a.ip, a.note].map { |cell| Tolzar::CsvCell.safe(cell) }
      end
    end
    send_data csv, filename: "super-admin-audit-#{Time.current.strftime('%Y%m%d')}.csv", type: 'text/csv'
  end

  private

  def read_filters
    @query = params[:q].to_s.strip.first(100)
    @from = date(params[:from])
    @to = date(params[:to])
    @sign_ins = params[:kind] == 'sign_ins'
  end

  def filtered
    scope = Tolzar::SuperAdminAudit.recent
    scope = scope.where(created_at: @from.beginning_of_day..) if @from
    scope = scope.where(created_at: ..@to.end_of_day) if @to
    scope = scope.where(action: SIGN_INS) if @sign_ins
    return scope if @query.blank?

    like = "%#{Tolzar::SuperAdminAudit.sanitize_sql_like(@query)}%"
    scope.where('email ILIKE :q OR path ILIKE :q OR action ILIKE :q OR controller ILIKE :q OR note ILIKE :q', q: like)
  end

  def date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def filter_params
    { q: @query.presence, from: @from&.iso8601, to: @to&.iso8601, kind: ('sign_ins' if @sign_ins) }.compact
  end
  helper_method :filter_params
end
