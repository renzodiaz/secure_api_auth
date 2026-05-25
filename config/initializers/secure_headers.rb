SecureHeaders::Configuration.default do |config|
  # Strict Transport Security — force HTTPS for 1 year
  config.hsts = "max-age=31536000; includeSubDomains"

  # Content Security Policy — control what resources can load
  config.csp = {
    default_src: %w['self'],
    script_src: %w['self'],
    connect_src: %w['self']
  }

  # Prevent clickjacking
  config.x_frame_options = "DENY"

  # Stop MIME type sniffing
  config.x_content_type_options = "nosniff"

  # Enable browser XSS filter
  config.x_xss_protection = "1; mode=block"

  # Control referrer information sent to other sites
  config.referrer_policy = "strict-origin-when-cross-origin"
end
