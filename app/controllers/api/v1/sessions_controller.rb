# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :doorkeeper_authorize!, only: %i[create refresh]

      # POST /api/v1/auth/login
      def create
        user = User.find_for_database_authentication(email: params[:email])

        if user&.valid_password?(params[:password])
          tokens = generate_tokens(user)
          set_auth_cookies(tokens)
          reset_session
          render json: {
            user: UserSerializer.new(user).as_json,
            expires_at: tokens[:expires_at],
            csrf_token: form_authenticity_token
          }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      # DELETE /api/v1/auth/logout
      def destroy
        revoke_tokens
        clear_auth_cookies
        render json: { message: "Logged out successfully" }
      end

      # POST /api/v1/auth/refresh
      def refresh
        refresh_token = cookies.encrypted[:refresh_token]
        return render json: { error: "No refresh token" }, status: :unauthorized if refresh_token.blank?

        existing = Doorkeeper::AccessToken.by_refresh_token(refresh_token)

        if existing.nil? || existing.revoked? || refresh_expired?(existing)
          clear_auth_cookies
          return render json: { error: "Expired session" }, status: :unauthorized
        end

        user = User.find_by(id: existing.resource_owner_id)
        existing.revoke

        tokens = generate_tokens(user)
        set_auth_cookies(tokens)
        reset_session
        render json: {
          user: UserSerializer.new(user).as_json,
          expires_at: tokens[:expires_at],
          csrf_token: form_authenticity_token
        }
      end

      private

      def skip_authorization?
        action_name.in?(%w[create refresh])
      end

      def generate_tokens(user)
        token = Doorkeeper::AccessToken.create!(
          resource_owner_id: user.id,
          expires_in: Doorkeeper.configuration.access_token_expires_in,
          scopes: "read write",
          use_refresh_token: true
        )
        {
          access_token: token.token,
          refresh_token: token.refresh_token,
          expires_at: token.expires_in.seconds.from_now.iso8601
        }
      end

      def set_auth_cookies(tokens)
        cookie_opts = { httponly: true, secure: Rails.env.production?, same_site: :lax }

        cookies.encrypted[:access_token] = cookie_opts.merge(
          value: tokens[:access_token],
          expires: 15.minutes.from_now
        )
        cookies.encrypted[:refresh_token] = cookie_opts.merge(
          value: tokens[:refresh_token],
          expires: 7.days.from_now
        )
      end

      def clear_auth_cookies
        cookies.delete(:access_token)
        cookies.delete(:refresh_token)
      end

      def revoke_tokens
        token = Doorkeeper::AccessToken.by_refresh_token(cookies.encrypted[:refresh_token])
        token&.revoke
      end

      def refresh_expired?(token)
        token.created_at + 7.days < Time.current
      end
    end
  end
end
