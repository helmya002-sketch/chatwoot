# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
class SuperAdmin::ApplicationController < Administrate::ApplicationController
  include ActionView::Helpers::TagHelper
  include ActionView::Context

  helper SuperAdmin::NavigationHelper, SuperAdmin::CommandBarHelper, SuperAdmin::UiHelper
  helper_method :render_vue_component
  # authenticiation done via devise : SuperAdmin Model
  before_action :authenticate_super_admin!
  # Tolzar Control Center: every change is audited (Tolzar::SuperAdminAudit; field names only, never values).
  after_action :tolzar_audit, unless: -> { request.get? || request.head? }

  # Override this value to specify the number of elements to display at a time
  # on index pages. Defaults to 20.
  # def records_per_page
  #   params[:per_page] || 20
  # end

  def order
    @order ||= Administrate::Order.new(
      params.fetch(resource_name, {}).fetch(:order, 'id'),
      params.fetch(resource_name, {}).fetch(:direction, 'desc')
    )
  end

  private

  def tolzar_audit
    Tolzar::SuperAdminAudit.record!(request: request, controller: controller_path, action: action_name,
                                    super_admin: current_super_admin, status: response.status, record_id: params[:id])
  end

  def render_vue_component(component_name, props = {})
    html_options = {
      id: 'app',
      data: {
        component_name: component_name,
        props: props.to_json
      }
    }
    content_tag(:div, '', html_options)
  end

  def invalid_action_perfomed
    # rubocop:disable Rails/I18nLocaleTexts
    flash[:error] = 'Invalid action performed'
    # rubocop:enable Rails/I18nLocaleTexts
    redirect_back(fallback_location: root_path)
  end
end
