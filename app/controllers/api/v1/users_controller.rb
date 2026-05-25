module Api
  module V1
    class UsersController < BaseController
      # GET /api/v1/me
      def me
        render json: { user: user_response(current_user) }, status: :ok
      end

      private

      def user_response(user)
        {
          id: user.id,
          email: user.email,
          created_at: user.created_at.iso8601
        }
      end
    end
  end
end
