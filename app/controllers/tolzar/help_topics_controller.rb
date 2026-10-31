# GET /tz/help/:topic: our help-centre article for a topic (Tolzar::HelpTopics), as a redirect to our own help
# centre. Public, like the help centre itself; it reads nothing private and never redirects to another host.
class Tolzar::HelpTopicsController < ActionController::Base
  def show
    redirect_to Tolzar::HelpTopics.path_for(params[:topic]), status: :found
  end
end
