module Api
  module V1
    class BaseController < ApplicationController
      # If resource not found fallback 404 not found
      rescue_from ActiveRecord::RecordNotFound,  with: :not_found
      rescue_from ActiveRecord::RecordInvalid,   with: :unprocessable_entity
      rescue_from Pundit::NotAuthorizedError,    with: :forbidden

      private

      def not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def unprocessable_entity(exception)
        render json: { errors: exception.record.errors.full_messages },
               status: :unprocessable_entity
      end

      def forbidden
        # Generic message — don't reveal why access was denied
        render json: { error: "Access denied" }, status: :forbidden
      end
    end
  end
end
