# frozen_string_literal: true

class Rack::Attack
  # ── Throttle login attempts by IP ──────────────────────────────
  # Max 5 login attempts per IP every 20 seconds
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/api/v1/auth/login" && req.post?
  end

  # ── Throttle login attempts by email ──────────────────────────
  # Max 5 login attempts per email every 20 seconds
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      req.params["email"].to_s.downcase.gsub(/\s+/, "")
    end
  end

  # ── General API rate limit ─────────────────────────────────────
  # Max 300 requests per IP per 5 minutes (normal usage)
  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/api")
  end

  # ── Custom response for throttled requests ─────────────────────
  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      },
      [ { error: "Too many requests. Please slow down." }.to_json ]
    ]
  end
end
