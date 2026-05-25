class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Pundit::Authorization  # Pundit authorization

  # Intersect the request and authorize unless skipped
  before_action :doorkeeper_authorize!, unless: :skip_authorization?

  private

  # We get the user using token object
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: doorkeeper_token.resource_owner_id) if doorkeeper_token
  end

  # For public endpoints
  def skip_authorization?
    false
  end
end
