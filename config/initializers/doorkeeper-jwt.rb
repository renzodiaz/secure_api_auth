Doorkeeper::JWT.configure do
  # Sign tokens with HS256 using your app's secret key
  secret_key Rails.application.credentials.secret_key_base
  signing_method :hs256

  # What goes inside each token
  token_payload do |opts|
    user = User.find(opts[:resource_owner_id])

    {
      iat: Time.current.to_i,                          # Issued at
      exp: (Time.current + opts[:expires_in]).to_i,  # Expiry timestamp
      jti: SecureRandom.uuid,                          # Unique token ID
      sub: user.id,                                     # Subject (user ID)
      email: user.email,
      scopes: opts[:scopes]
    }
  end

  secret_key_path nil
  use_application_secret false
end