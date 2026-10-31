# Tolzar Control Center: the super-admin audit log (Tolzar::SuperAdminAudit), newest first, searchable by e-mail,
# path or action. Read-only: rows are never edited or deleted from the web.
class SuperAdmin::TolzarAuditsController < SuperAdmin::ApplicationController
  PER_PAGE = 100

  EXPORT_LIMIT = 10_000

  def show
    @query = params[:q].to_s.strip.first(100)
    scope = filtered
    @page = [params[:page].to_i, 1].max
    @audits = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @audits.size > PER_PAGE
    @audits = @audits.first(PER_PAGE)
  end

  # The same search as CSV (newest first, at most EXPORT_LIMIT rows); field names only, as stored.
  def export
    @query = params[:q].to_s.strip.first(100)
    csv = CSV.generate do |out|
      out << %w[at email method controller action path record fields status ip]
      filtered.limit(EXPORT_LIMIT).each do |a|
        out << [a.created_at.utc.iso8601, a.email, a.http_method, a.controller, a.action, a.path, a.record_id,
                Array(a.fields).join(' '), a.status, a.ip]
      end
    end
    send_data csv, filename: "super-admin-audit-#{Time.current.strftime('%Y%m%d')}.csv", type: 'text/csv'
  end

  private

  def filtered
    scope = Tolzar::SuperAdminAudit.recent
    return scope if @query.blank?

    like = "%#{Tolzar::SuperAdminAudit.sanitize_sql_like(@query)}%"
    scope.where('email ILIKE :q OR path ILIKE :q OR action ILIKE :q OR controller ILIKE :q', q: like)
  end
end
