# frozen_string_literal: true

Rails.application.configure do
  config.lograge.enabled = true

  config.lograge.custom_options = lambda do |event|
    {
      time: Time.current.iso8601,
      host: event.payload[:host],
      user_id: event.payload[:user_id]
    }
  end
end
