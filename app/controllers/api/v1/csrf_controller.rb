# frozen_string_literal: true

module Api
  module V1
    class CsrfController < BaseController
      skip_before_action :doorkeeper_authorize!

      # GET /api/v1/csrf_token
      def show
        render json: { csrf_token: form_authenticity_token }
      end

      private

      def skip_authorization?
        true
      end
    end
  end
end
