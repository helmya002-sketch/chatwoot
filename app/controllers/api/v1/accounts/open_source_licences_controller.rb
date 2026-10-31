# Tolzar: GET /api/v1/accounts/:account_id/open_source_licences, the notices behind the profile menu's
# "Open-source licences" page (Tolzar::OpenSourceNotices). Every signed-in member of the workspace may read it.
class Api::V1::Accounts::OpenSourceLicencesController < Api::V1::Accounts::BaseController
  def index
    render json: Tolzar::OpenSourceNotices.call(Current.account.id)
  end
end
