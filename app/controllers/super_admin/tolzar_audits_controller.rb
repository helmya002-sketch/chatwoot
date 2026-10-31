# Tolzar Control Center: the super-admin audit log (Tolzar::SuperAdminAudit), newest first, searchable by e-mail,
# path or action. Read-only: rows are never edited or deleted from the web.
class SuperAdmin::TolzarAuditsController < SuperAdmin::ApplicationController
  PER_PAGE = 100

  def show
    @query = params[:q].to_s.strip.first(100)
    scope = Tolzar::SuperAdminAudit.recent
    if @query.present?
      like = "%#{Tolzar::SuperAdminAudit.sanitize_sql_like(@query)}%"
      scope = scope.where('email ILIKE :q OR path ILIKE :q OR action ILIKE :q OR controller ILIKE :q', q: like)
    end
    @page = [params[:page].to_i, 1].max
    @audits = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @audits.size > PER_PAGE
    @audits = @audits.first(PER_PAGE)
  end
end
