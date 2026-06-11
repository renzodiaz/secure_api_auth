# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include Pundit::Authorization

  protect_from_forgery with: :exception

  before_action :doorkeeper_authorize!, unless: :skip_authorization?

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: doorkeeper_token.resource_owner_id) if doorkeeper_token
  end

  def skip_authorization?
    false
  end

  def append_info_to_payload(payload)
    super
    payload[:host]    = request.host
    payload[:user_id] = current_user&.id if doorkeeper_token
  end
end
