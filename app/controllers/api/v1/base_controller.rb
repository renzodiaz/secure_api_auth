# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      # StandardError must be first (lowest priority) so specific handlers below take precedence
      rescue_from StandardError,                              with: :internal_server_error
      rescue_from ActiveRecord::RecordNotFound,               with: :not_found
      rescue_from ActiveRecord::RecordInvalid,                with: :unprocessable_entity
      rescue_from Pundit::NotAuthorizedError,                 with: :forbidden
      rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf_token

      private

      def not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def unprocessable_entity(exception)
        render json: { errors: exception.record.errors.full_messages },
               status: :unprocessable_entity
      end

      def forbidden
        render json: { error: "Access denied" }, status: :forbidden
      end

      def invalid_csrf_token
        render json: { error: "Invalid CSRF token" }, status: :forbidden
      end

      def internal_server_error(exception)
        raise exception unless Rails.env.production?

        Rails.logger.error("#{exception.class}: #{exception.message}")
        render json: { error: "Internal server error" }, status: :internal_server_error
      end
    end
  end
end
