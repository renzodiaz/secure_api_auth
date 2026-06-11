# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      # GET /api/v1/me
      def me
        render json: { user: UserSerializer.new(current_user).as_json }, status: :ok
      end
    end
  end
end
