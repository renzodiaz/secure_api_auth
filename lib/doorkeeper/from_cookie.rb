# frozen_string_literal: true

module Doorkeeper
  module FromCookie
    module_function

    def call(request)
      # Read the encrypted access token from the httpOnly cookie
      request.cookie_jar.encrypted[:access_token]
    end
  end
end
