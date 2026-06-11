Rails.application.routes.draw do
  use_doorkeeper do
    skip_controllers :authorizations, :applications,
                     :authorized_applications, :tokens
  end

  namespace :api do
    namespace :v1 do
      # CSRF token for SPA clients
      get "csrf_token", to: "csrf#show"

      # Authentication endpoints
      post   "auth/register", to: "registrations#create"
      post   "auth/login",    to: "sessions#create"
      delete "auth/logout",   to: "sessions#destroy"
      post   "auth/refresh",  to: "sessions#refresh"

      # Protected resources
      get "me", to: "users#me"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
