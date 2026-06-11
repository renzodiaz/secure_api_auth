# Part 4: CSRF Tokens, Force SSL, Production Error Handling, and Serializers

Hey folks 👋

Welcome back. In [Part 3](https://dev.to/renzodiaz/...) we built all five auth endpoints, added Rack-Attack rate limiting, hardened the HTTP headers with `secure_headers`, and set up Lograge for structured logs. The API is functional and most of the security checklist is green.

But we left three vectors partially open, and we made a design debt: hand-rolling response hashes in every controller. Today we close all of that.

Here is what we are doing in Part 4:

* **Explicit CSRF tokens** for every state-changing endpoint
* **Session fixation protection** with `reset_session` on login and refresh
* **`force_ssl`** in production, the last piece of MITM defense
* **Production error handler** so unhandled exceptions never leak stack traces
* **Alba serializers** to replace the hand-rolled response hashes across controllers

If your Part 3 project is open, let's continue.

## A quick word on what CSRF actually means for a cookie-based API

In Part 3 we used `SameSite=Lax` cookies and pinned CORS origins. Together those already stop most CSRF attacks. So why add explicit CSRF tokens on top?

`SameSite=Lax` tells the browser: "don't send this cookie on cross-site requests unless it's a top-level GET." That blocks the classic CSRF attack where a malicious site submits a form to your API. But `SameSite` is a browser-level protection, and its behavior has edge cases across older browsers, redirect chains, and certain same-site subdomain scenarios.

Explicit CSRF tokens add a second layer that doesn't depend on the browser getting `SameSite` right. The server issues a token, the client must echo it back, and an attacker who can only influence what cookies the browser sends can never produce the right header value.

There's also a subtler attack called **login CSRF**. An attacker forges a login request that authenticates the victim as the attacker's own account. The victim thinks they're using the site normally but their actions — uploading documents, saving payment details — land in the attacker's account. The only way to prevent that is to protect the login endpoint itself, which we do here.

## Step 1. Include CSRF protection in ApplicationController

Rails 8 API mode excludes `ActionController::RequestForgeryProtection` by default. We have to bring it back in.

Edit `app/controllers/application_controller.rb`:

```ruby
# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include Pundit::Authorization

  protect_from_forgery with: :exception

  before_action :doorkeeper_authorize!, unless: :skip_authorization?

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: doorkeeper_token.resource_owner_id) if doorkeeper_token
  end

  def skip_authorization?
    false
  end

  def append_info_to_payload(payload)
    super
    payload[:host]    = request.host
    payload[:user_id] = current_user&.id if doorkeeper_token
  end
end
```

Three things changed:

1. `include ActionController::RequestForgeryProtection` brings the CSRF machinery in.
2. `protect_from_forgery with: :exception` makes any request with a missing or invalid CSRF token raise `ActionController::InvalidAuthenticityToken`. We will rescue that shortly.
3. `append_info_to_payload` is the hook Lograge calls to let you attach custom fields. We add `host` and `user_id` so every log line carries them. I left this out of Part 3 by accident.

`protect_from_forgery` only fires on non-GET requests (POST, PUT, PATCH, DELETE). GET requests don't need CSRF tokens and never will.

## Step 2. Handle the CSRF error in BaseController

We need to rescue `ActionController::InvalidAuthenticityToken` and return a JSON response. While we're here, we also add a `rescue_from StandardError` for production: no unhandled exception should ever reach the client as a stack trace.

Edit `app/controllers/api/v1/base_controller.rb`:

```ruby
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
```

The ordering of `rescue_from` matters. Rails searches handlers from the last declared to the first (last in wins). By declaring `rescue_from StandardError` first and the specific errors after, each specific handler has higher priority. An `ActiveRecord::RecordNotFound` matches the `not_found` handler before it ever reaches `internal_server_error`.

The `internal_server_error` handler re-raises the exception in non-production environments. This means your development server still shows the full error (useful for debugging), but production callers only ever see `"Internal server error"`.

🛡️ **Mitigation in action: Verbose Error Messages (Part 1, vector 11)**

This closes the last gap from Part 3. Stack traces, internal paths, database errors — none of it reaches the client in production. It all goes to the logger, which is where it belongs.

## Step 3. Add the CSRF token endpoint

The client needs a way to get a CSRF token before making its first state-changing request. A dedicated GET endpoint is the cleanest approach.

Create `app/controllers/api/v1/csrf_controller.rb`:

```ruby
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
```

`form_authenticity_token` generates a masked token tied to the current session. The session itself is stored in the `_secure_api_session` cookie (configured in Part 2). Every call generates a fresh masked version of the same underlying session token. All those masked versions are valid — the server unmasks them before comparing.

Wire it up in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  use_doorkeeper do
    skip_controllers :authorizations, :applications,
                     :authorized_applications, :tokens
  end

  namespace :api do
    namespace :v1 do
      # CSRF token for SPA clients
      get "csrf_token", to: "csrf#show"

      # Authentication endpoints
      post   "auth/register", to: "registrations#create"
      post   "auth/login",    to: "sessions#create"
      delete "auth/logout",   to: "sessions#destroy"
      post   "auth/refresh",  to: "sessions#refresh"

      # Protected resources
      get "me", to: "users#me"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

## Step 4. Update SessionsController: session fixation + CSRF token in response

Two changes here: `reset_session` on login and refresh, and returning the CSRF token so the client doesn't need to make a second round-trip after authenticating.

Edit `app/controllers/api/v1/sessions_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :doorkeeper_authorize!, only: %i[create refresh]

      # POST /api/v1/auth/login
      def create
        user = User.find_for_database_authentication(email: params[:email])

        if user&.valid_password?(params[:password])
          tokens = generate_tokens(user)
          set_auth_cookies(tokens)
          reset_session
          render json: {
            user: UserSerializer.new(user).as_json,
            expires_at: tokens[:expires_at],
            csrf_token: form_authenticity_token
          }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      # DELETE /api/v1/auth/logout
      def destroy
        revoke_tokens
        clear_auth_cookies
        render json: { message: "Logged out successfully" }
      end

      # POST /api/v1/auth/refresh
      def refresh
        refresh_token = cookies.encrypted[:refresh_token]
        return render json: { error: "No refresh token" }, status: :unauthorized if refresh_token.blank?

        existing = Doorkeeper::AccessToken.by_refresh_token(refresh_token)

        if existing.nil? || existing.revoked? || refresh_expired?(existing)
          clear_auth_cookies
          return render json: { error: "Expired session" }, status: :unauthorized
        end

        user = User.find_by(id: existing.resource_owner_id)
        existing.revoke

        tokens = generate_tokens(user)
        set_auth_cookies(tokens)
        reset_session
        render json: {
          user: UserSerializer.new(user).as_json,
          expires_at: tokens[:expires_at],
          csrf_token: form_authenticity_token
        }
      end

      private

      def skip_authorization?
        action_name.in?(%w[create refresh])
      end

      def generate_tokens(user)
        token = Doorkeeper::AccessToken.create!(
          resource_owner_id: user.id,
          expires_in: Doorkeeper.configuration.access_token_expires_in,
          scopes: "read write",
          use_refresh_token: true
        )
        {
          access_token: token.token,
          refresh_token: token.refresh_token,
          expires_at: token.expires_in.seconds.from_now.iso8601
        }
      end

      def set_auth_cookies(tokens)
        cookie_opts = { httponly: true, secure: Rails.env.production?, same_site: :lax }

        cookies.encrypted[:access_token] = cookie_opts.merge(
          value: tokens[:access_token],
          expires: 15.minutes.from_now
        )
        cookies.encrypted[:refresh_token] = cookie_opts.merge(
          value: tokens[:refresh_token],
          expires: 7.days.from_now
        )
      end

      def clear_auth_cookies
        cookies.delete(:access_token)
        cookies.delete(:refresh_token)
      end

      def revoke_tokens
        token = Doorkeeper::AccessToken.by_refresh_token(cookies.encrypted[:refresh_token])
        token&.revoke
      end

      def refresh_expired?(token)
        token.created_at + 7.days < Time.current
      end
    end
  end
end
```

**Why `reset_session`?** Before this change, if an attacker somehow knew or influenced the user's session ID before login (a session fixation attack), they could reuse that session ID after the victim authenticated and hijack the session. `reset_session` wipes the old session and generates a new ID on every login and refresh, so there is no pre-login session to fixate on.

**Why return `csrf_token` in the login response?** The client already made a round-trip to log in. We return the CSRF token right there in the response body, so it doesn't need to call `GET /csrf_token` separately after logging in. The client stores the token in JS memory (not in localStorage, not in a cookie) and sends it as the `X-CSRF-Token` header on every subsequent state-changing request.

🛡️ **Mitigation in action: CSRF (Part 1, vector 3)**

Combined with `SameSite=Lax` and pinned CORS origins from Part 2 and 3, this closes the CSRF vector completely. We now have three layers: the browser won't send cookies cross-site (SameSite), the server rejects unknown origins (CORS), and a random site can never produce a valid CSRF token (explicit tokens).

## Step 5. Add serializers with Alba

Add the gem:

```ruby
# Serialization
gem "alba"
```

Then:

```bash
bundle install
```

Create `app/serializers/user_serializer.rb`:

```ruby
# frozen_string_literal: true

class UserSerializer
  include Alba::Resource

  attributes :id, :email

  attribute :created_at do |user|
    user.created_at.iso8601
  end
end
```

That's the whole serializer. `attributes` declares fields by name; `attribute` with a block lets you transform a value before it goes out. The `created_at` block converts the ActiveRecord timestamp to an ISO 8601 string so the client always gets a consistent format regardless of Rails serialization settings.

Update `app/controllers/api/v1/users_controller.rb`:

```ruby
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
```

The `as_json` call (instead of `serialize`) returns a Ruby hash that Rails can embed inside the larger response hash. If you called `serialize` here it would return a JSON string, and Rails would end up double-encoding it.

🛡️ **Mitigation in action: Excessive Data Exposure (Part 1, vector 8)**

With serializers in place, the contract is explicit and enforced in one place. Adding a new column to the `users` table — even a sensitive one — will never accidentally appear in API responses. The serializer is the whitelist. Nothing goes out unless it's listed there.

## Step 6. Enable `force_ssl` in production

Uncomment one line in `config/environments/production.rb`:

```ruby
# Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
config.force_ssl = true
```

`force_ssl` does three things at the Rails level:

1. Redirects any HTTP request to HTTPS before it reaches your controllers.
2. Sets the `Secure` flag on all cookies (so they are never sent over plain HTTP).
3. Adds an HSTS header (`Strict-Transport-Security`) that instructs browsers to remember the HTTPS-only policy for a configurable duration.

We already set HSTS manually in the `secure_headers` initializer in Part 3. `force_ssl` being enabled means Rails adds its own HSTS on top. The two don't conflict — the browser just sees the header and caches the policy. But `force_ssl` is the one that actually enforces the redirect, which `secure_headers` alone doesn't do.

🛡️ **Mitigation in action: MITM (Part 1, vector 9)**

The chain is now complete: `force_ssl` redirects HTTP → HTTPS, `secure_headers` sets HSTS so browsers remember not to try HTTP again, and `Secure` cookies ensure auth tokens are never sent in the clear. A network-level attacker has nothing to intercept.

## Step 7. Test the updated flow with curl

The CSRF requirement changes the curl commands from Part 3. Here's the updated flow.

Start the server:

```bash
bin/rails server
```

**Step 1 — get a CSRF token:**

```bash
CSRF=$(curl -s -c cookies.txt http://localhost:3000/api/v1/csrf_token | ruby -e "require 'json'; puts JSON.parse(STDIN.read)['csrf_token']")
echo $CSRF
```

We save the session cookie with `-c cookies.txt`. The CSRF token is stored in shell variable `$CSRF`.

**Step 2 — register:**

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF" \
  -b cookies.txt -c cookies.txt \
  -d '{"user": {"email": "me@example.com", "password": "s3cr3tP@ss", "password_confirmation": "s3cr3tP@ss"}}'
```

**Step 3 — login and capture the new CSRF token:**

```bash
LOGIN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF" \
  -b cookies.txt -c cookies.txt \
  -d '{"email": "me@example.com", "password": "s3cr3tP@ss"}')

echo $LOGIN
CSRF=$(echo $LOGIN | ruby -e "require 'json'; puts JSON.parse(STDIN.read)['csrf_token']")
```

After login, `reset_session` invalidated the old session and generated a new one. The response body carries the new CSRF token, which we capture into `$CSRF` again.

**Step 4 — call the protected endpoint:**

```bash
curl http://localhost:3000/api/v1/me -b cookies.txt
```

This is a GET so no CSRF token needed.

**Step 5 — refresh:**

```bash
REFRESH=$(curl -s -X POST http://localhost:3000/api/v1/auth/refresh \
  -H "X-CSRF-Token: $CSRF" \
  -b cookies.txt -c cookies.txt)

echo $REFRESH
CSRF=$(echo $REFRESH | ruby -e "require 'json'; puts JSON.parse(STDIN.read)['csrf_token']")
```

Refresh also calls `reset_session`, so again we capture the new token from the response.

**Step 6 — logout:**

```bash
curl -X DELETE http://localhost:3000/api/v1/auth/logout \
  -H "X-CSRF-Token: $CSRF" \
  -b cookies.txt
```

**What happens without the CSRF header?**

Try sending a POST without `X-CSRF-Token` and you'll get:

```json
{ "error": "Invalid CSRF token" }
```

with a `403 Forbidden`. Not a stack trace. Not a Rails error page. Just the response we defined in `invalid_csrf_token`.

## Where we are now

The security checklist is nearly complete. CSRF is fully mitigated, SSL is enforced in production, no unhandled exception ever leaks to a client, and serializers mean accidental data exposure through new model fields is no longer possible.

## Progress tracker: security vectors from Part 1

| # | Attack vector | Status | Where |
|---|---------------|--------|-------|
| 1 | XSS | 🟢 Mitigated | HttpOnly cookies (Part 2) + strict CSP headers (Part 3) |
| 2 | SQL Injection | 🟢 Mitigated | Active Record + strong params throughout controllers |
| 3 | CSRF | 🟢 Mitigated | SameSite cookies + pinned CORS + explicit CSRF tokens + session fixation protection (Step 1–4) |
| 4 | Brute Force | 🟢 Mitigated | bcrypt + Rack-Attack IP and email throttles (Part 3) |
| 5 | User Enumeration | 🟢 Mitigated | Generic "Invalid credentials" message (Part 3) |
| 6 | IDOR | 🔴 Not yet | Will be addressed with Pundit policies + Sqids. Part 5. |
| 7 | Mass Assignment | 🟢 Mitigated | Strong params in every controller (Part 3) |
| 8 | Excessive Data Exposure | 🟢 Mitigated | Alba serializers with explicit field whitelisting (Step 5) |
| 9 | MITM | 🟢 Mitigated | HSTS + secure cookies + `force_ssl` in production (Step 6) |
| 10 | Token Theft | 🟢 Mitigated | HttpOnly + encrypted cookies + short tokens + rotation + revocation on logout (Part 2–3) |
| 11 | Verbose Error Messages | 🟢 Mitigated | Generic 403/404/500 responses + production error rescue (Step 2) |

Legend: 🟢 Covered, 🟡 Partial, 🔴 Pending

One vector remains: IDOR. It only becomes a real problem once we have resources that belong to users, which is exactly what we build next.

## Coming up in Part 5

We add the first real resource, `Post`, and wire up Pundit policies so users can only access their own records. We also introduce Sqids so database IDs never appear in URLs directly. After that the API is ready for more complex authorization scenarios.

Follow along if you want to get notified when the next part is published. And if anything broke or didn't make sense, drop a comment.
