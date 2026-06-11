I'm writing a secure rails api tutorial with ruby on rails 8, I have wrote in parts so this is how it looks the part one:

Hi folks👋! 

In this post I want to share something I wish I had when I started building APIs with Ruby on Rails: a practical guide that takes security seriously from the beginning.

When I built my first REST API, most tutorials I found were focused on getting something running quickly. They were great for learning the basics, but they usually skipped important topics like API versioning, authentication strategy, authorization, and security.

Even when using AI tools to generate a “secure API”, the result is often still insecure unless you already understand the threats you are trying to protect against. Security is not something you get automatically. You need to know what problems you are solving and why the protections matter.

I ended up reading API design books, OWASP documentation, and real-world breach reports before I finally felt like I understood what I was building, I've put all in practice. This post is the guide I wish I had back then.

In this series we are going to build a production-ready Rails 8 API with authentication, authorization, rate limiting, secure cookies, security headers, and other important protections. I also want to explain the reasoning behind each decision, not just copy-paste code without context.

Before writing any code, let’s first understand the main attack vectors we need to defend against.

## The attack vectors we are defending against

###1. XSS (Cross-Site Scripting)

**🚨 Threat:**
XSS happens when an attacker injects malicious JavaScript into content that later gets rendered in another user’s browser. In API-driven applications, one of the biggest risks is token theft. If JWTs are stored in `localStorage`, a malicious script can read and steal them immediately.

**🛡️ Mitigation:**
Avoid storing authentication tokens in `localStorage` or other browser-accessible storage. Instead, store them in secure `HttpOnly` cookies so JavaScript cannot access them. Cookies should also use the `Secure` and `SameSite` attributes. Any user-generated content rendered in the frontend should be properly escaped or sanitized.

###2. SQL Injection

**🚨 Threat:**
SQL Injection happens when user input is inserted directly into a SQL query without proper sanitization. An attacker can manipulate the query to bypass authentication, read sensitive data, or modify the database.

**🛡️ Mitigation:**
Avoid interpolating user input directly into SQL queries. In Rails, prefer Active Record methods like `where`, `find_by`, and parameterized queries, which automatically sanitize input. If raw SQL is unavoidable, use bound parameters instead of string interpolation. You should also validate input, use strong parameters, and follow the principle of least privilege for database accounts.

###3. CSRF (Cross-Site Request Forgery)

**🚨 Threat:**
CSRF happens when a malicious website tricks a logged-in user’s browser into sending authenticated requests to your application using automatically attached cookies.

This is especially important in Rails APIs using session cookies or JWTs stored in `HttpOnly` cookies. Even though JavaScript cannot read those cookies, the browser still sends them automatically with requests.

An attacker could potentially trigger actions like changing account settings, creating resources, or deleting data without the user realizing it.

**🛡️ Mitigation:**
Enable CSRF protection for any cookie-based authentication flow. In Rails, use `protect_from_forgery` and require valid CSRF tokens for state-changing requests like `POST`, `PUT`, `PATCH`, and `DELETE`.

Authentication cookies should also use:

- `HttpOnly`

- `Secure`

- `SameSite=Lax` or `SameSite=Strict`

You should also validate `Origin` and `Referer` headers and keep CORS restricted to trusted frontend domains.

If the browser automatically sends authentication, CSRF protection still matters, even if the API itself is technically stateless.

###4. Brute Force

**🚨 Threat:**
Brute force attacks happen when an attacker repeatedly tries large numbers of username and password combinations against your login endpoint.

This commonly targets login forms, password reset endpoints, and authentication APIs. Successful attacks can lead to account compromise, credential stuffing, and unnecessary server load.

**🛡️ Mitigation:**
Use rate limiting on authentication-related endpoints. In Rails, tools like `Rack::Attack` can throttle repeated requests by IP address, email, or both.

You should also:

- temporarily lock accounts after repeated failures

- require strong passwords

- detect suspicious login activity

- avoid revealing whether an account exists

- consider CAPTCHA or step-up verification after suspicious behavior

###5. User Enumeration

**🚨 Threat:**
User enumeration happens when an application reveals whether an account exists through different error messages.

For example:

- “Email not found”

- “Incorrect password”

An attacker can use these differences to discover valid accounts and later target them with brute force attacks, phishing, or credential stuffing.

**🛡️ Mitigation:**
Return consistent responses during login, password reset, and account recovery flows.

Instead of exposing whether the email exists, use generic responses such as:

- “Invalid credentials”

- “If an account exists, instructions have been sent”

You should also rate limit these endpoints and monitor repeated probing attempts.

###6. IDOR (Insecure Direct Object Reference)

**🚨 Threat:**
IDOR happens when users can access resources they do not own by changing identifiers in URLs or request parameters.

For example:

```ruby

User.find(params[:id])

```

If ownership checks are missing, changing `/users/42` to `/users/43` could expose another user’s data.

**🛡️ Mitigation:**
Always scope records through the authenticated user or an authorization policy.

Instead of:

```ruby

Post.find(params[:id])

```

Prefer:

```ruby

current_user.posts.find(params[:id])

```

Authorization libraries like Pundit or CanCanCan also help enforce access rules consistently across the application. I also avoid exposing raw database IDs directly to the frontend. Instead, I use [Sqids](https://sqids.org/ruby)￼to generate less predictable public IDs, which helps reduce simple enumeration attacks.

###7. Mass Assignment

**🚨 Threat:**
Mass assignment happens when the application accepts user input and blindly assigns it to model attributes.

An attacker could submit unexpected fields such as:

```json

{

  "admin": true

}

```

If those fields are not filtered properly, the attacker may gain elevated privileges or modify protected data.

**🛡️ Mitigation:**
Use strong parameters in every controller.

In Rails, always whitelist allowed attributes using:

```ruby

params.require(:user).permit(:email, :password)

```

Never pass raw `params` directly into `create` or `update`.

Sensitive fields like roles, permissions, ownership fields, or account status flags should never be user-assignable.

###8. Excessive Data Exposure

**🚨 Threat:**
Excessive data exposure happens when an API returns more information than the client actually needs.

This often happens when entire Active Record objects are rendered directly into JSON responses.

Sensitive data such as password digests, internal IDs, permissions, API keys, or private metadata may accidentally leak through the API.

**🛡️ Mitigation:**
Only return the fields the client actually needs.

Instead of blindly rendering full objects:

```ruby

render json: @user

```

Use serializers or custom JSON responses that explicitly define safe attributes.

Sensitive fields should never appear in API responses.

You should also regularly review serialized responses to make sure no internal data is leaking unintentionally.

###9. MITM (Man-in-the-Middle)

**🚨 Threat:**
A Man-in-the-Middle attack happens when an attacker intercepts traffic between the client and server.

Without HTTPS, credentials, tokens, cookies, and other sensitive data can travel in plain text and be stolen or modified.

Attackers on the same network, malicious proxies, or compromised routers can hijack sessions or impersonate users.

**🛡️ Mitigation:**
Always enforce HTTPS.

In Rails, enable:

```ruby

config.force_ssl = true

```

This redirects insecure requests and ensures cookies are only sent over encrypted connections.

Authentication cookies should also use the `Secure` and `HttpOnly` flags.

You should additionally enable HSTS headers and avoid loading insecure mixed-content resources.

###10. Token Theft

**🚨 Threat:**
Token theft happens when an attacker gains access to a valid authentication token and uses it to impersonate a user.

Stolen JWTs can come from XSS attacks, insecure storage, leaked logs, browser extensions, compromised devices, or intercepted traffic.

If tokens remain valid for a long time, the attacker may keep access even after the user notices something is wrong.

**🛡️ Mitigation:**
Reduce token exposure and keep token lifetimes short.

Prefer storing tokens in secure `HttpOnly` cookies instead of `localStorage`.

Use:

- short-lived access tokens

- refresh token rotation

- token revocation mechanisms

You should also avoid exposing tokens in logs or URLs and protect the application against XSS vulnerabilities.

###11. Verbose Error Messages

**🚨 Threat:**
Verbose error messages expose internal application details to attackers.

Stack traces, database errors, framework versions, SQL queries, and file paths can all help attackers understand how the system works and make exploitation easier.

**🛡️ Mitigation:**
Production applications should return generic and safe error responses.

Instead of exposing internal exceptions, return messages such as:

- `Internal Server Error`

- `Invalid request`

Detailed errors should only be logged internally for debugging.

In Rails, make sure debug pages and detailed exceptions are disabled in production.

## Final Thoughts

These are some of the most important security risks to think about when building APIs, and we will revisit them throughout this series as we implement each feature step by step.

In Part 2 we will start building the Rails 8 API from scratch and set up the project foundation correctly from the beginning, including authentication, secure configuration, and API structure.

Follow along if you want to get notified when the next part is published.

now this is how it looks part 3:

Hey folks 👋

Welcome back. In [Part 2](https://dev.to/renzodiaz/build-a-secure-api-with-rails-8-part-2-authentication-foundations-2fo5) we laid the foundation: a Rails 8 API with a User model, password hashing through Devise, OAuth2 password grant via Doorkeeper, JWT access tokens, refresh tokens, and HttpOnly cookie storage. Solid base, but no actual endpoints yet.

Today we fix that. We are going to write the auth controllers (register, login, logout, refresh, and me), and while we do it we'll knock out four more vectors from the tracker: CSRF, User Enumeration, Mass Assignment, and Excessive Data Exposure. We'll also add rate limiting, encrypted DB fields, secure HTTP headers, and structured logging.

Heads up before we start: this part is longer than Part 2. I thought about splitting it again, but everything here belongs together. Controllers without rate limiting are half-protected, and rate limiting without controllers to protect is pointless. So grab a coffee and let's go.

## What we are building in Part 3

* Pundit for authorization, Rack-CORS to control who can talk to our API
* A versioned API structure (`/api/v1/...`) so we don't paint ourselves into a corner later
* Auth controllers: register, login, logout, refresh, and a `me` endpoint
* Rate limiting with Rack-Attack to slow down brute force attempts
* Encrypted DB fields with Lockbox for sensitive data
* HTTP security headers with secure_headers
* Structured logs with Lograge

If your [Part 2](https://dev.to/renzodiaz/build-a-secure-api-with-rails-8-part-2-authentication-foundations-2fo5) project is sitting on your disk, open it up and let's continue.

## Step 1. Add Pundit and Rack-CORS

Pundit handles authorization (the "what is this user allowed to do" question, as opposed to "who is this user" which Devise already answered). Rack-CORS controls which domains are allowed to make requests to our API from a browser.

Open your Gemfile:

```ruby
# Authentication & Authorization
# ...
gem 'pundit'

# Security
gem 'rack-cors'
```

Then:

```bash
bundle install
bin/rails g pundit:install
```

The generator creates `app/policies/application_policy.rb`, which we'll use later when we add real resources.

## Step 2. Configure CORS

Open `config/initializers/cors.rb` and replace it with:

```ruby
# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # In production, replace with your real frontend domain
    origins ENV.fetch("FRONTEND_URL", "http://localhost:5173")

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: true,
      expose: %w[X-CSRF-Token]
  end
end
```

A mistake I have personally made and seen a hundred times in code reviews: don't use `origins '*'` with `credentials: true`. Browsers will reject it outright, and even if they didn't, it would mean any website on the internet could make authenticated requests to your API. Always pin the origin to your real frontend domain (or domains, you can pass an array).

The `credentials: true` part is required because our auth lives in cookies. Without it, the browser won't attach the session cookie to cross-origin requests, and login will appear to "work" but every following request will look anonymous. I spent an embarrassing afternoon on that one.

🛡️ **Mitigation in action: CSRF foundation (Part 1, vector 3)**

Locking down origins is the first half of CSRF defense. Combined with `SameSite=Lax` from Part 2, a random attacker site can't trick a logged-in user's browser into hitting our API. We'll add explicit CSRF tokens later in this post for the parts that need them.

## Step 3. Update ApplicationController

`ApplicationController` is the entry point for every request. Everything else inherits from it. We need it to do three things: include cookie support, plug in Pundit, and require a valid Doorkeeper token by default (so endpoints are private unless we explicitly say otherwise).

Edit `app/controllers/application_controller.rb`:

```ruby
# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Pundit::Authorization

  before_action :doorkeeper_authorize!, unless: :skip_authorization?

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: doorkeeper_token.resource_owner_id) if doorkeeper_token
  end

  def skip_authorization?
    false
  end
end
```

The `skip_authorization?` method defaults to `false`, meaning every endpoint requires a token. Individual controllers (like login and register, which obviously can't require you to already be logged in) will override it to return `true` for specific actions. I prefer this "deny by default" pattern because forgetting to add auth is a much more common bug than forgetting to mark something public.

One thing I want to call out: `current_user` looks up the user from `doorkeeper_token.resource_owner_id`. That `resource_owner_id` was set back in Part 2 when Doorkeeper issued the token. The JWT itself carries the user ID, so we are NOT hitting the database to verify the token, only to load the user record. That's the whole point of JWT.

## Step 4. Create the versioned BaseController

Eventually you will want to release a v2 of your API without breaking the v1 clients that are already in the wild. There are several ways to version an API (custom headers, content negotiation, URL paths). I've used all three and I'll save you the suspense: URL path versioning (`/api/v1/...`) is the easiest to debug, the easiest to document, and the easiest for new teammates to understand. We're going with that.

Create the folder structure:

```bash
mkdir -p app/controllers/api/v1
```

Then create `app/controllers/api/v1/base_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid,  with: :unprocessable_entity
      rescue_from Pundit::NotAuthorizedError,   with: :forbidden

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
    end
  end
end
```

Every controller from now on inherits from `BaseController`, which means every controller gets these three error handlers for free.

🛡️ **Mitigation in action: Verbose Error Messages (Part 1, vector 11)**

Notice that `forbidden` returns a generic "Access denied" message. It does NOT say "you don't own this record" or "your role is missing the `admin` scope". That detail is gold for an attacker probing your API. Same idea for `not_found`: we just say "Not found", we don't leak whether the record exists but is private, or doesn't exist at all.

We'll fully button up production error handling in Part 4, but this is the start.

## Step 5. SessionsController (login, logout, refresh)

Now the fun part. The sessions controller handles login, logout, and refresh. I'm going to paste the whole thing and then walk through the parts that matter.

Create `app/controllers/api/v1/sessions_controller.rb`:

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
          render json: { user: user_response(user), expires_at: tokens[:expires_at] }
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
        render json: { user: user_response(user), expires_at: tokens[:expires_at] }
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

      def user_response(user)
        { id: user.id, email: user.email }
      end
    end
  end
end
```

A few things worth pausing on.

**The login response is intentionally vague.** When credentials are wrong, we return `"Invalid credentials"`. Not "no user with that email", not "wrong password". Both of those leak information. The first time I built an API I had a friendly "Email not found, would you like to sign up?" message. That message is also a free oracle for an attacker to verify whether `victim@gmail.com` has an account on your platform. Don't help them.

🛡️ **Mitigation in action: User Enumeration (Part 1, vector 5)**

Generic auth errors are the single cheapest mitigation in this whole series. Cost: zero. Benefit: attackers can't build a list of valid emails by hitting your login endpoint.

**Refresh tokens are rotated.** Look at the `refresh` action: when a refresh token is used, we immediately call `existing.revoke` on it before issuing a new one. This means a refresh token is single-use. If an attacker manages to steal a refresh token from your cookies and uses it, the legitimate user's next refresh will fail (because the attacker already burned it), and you can detect the anomaly. We're not implementing the detection part today, but the rotation alone already raises the cost of an attack significantly.

**Logout actually revokes the token.** A surprising number of "logout" endpoints I have reviewed in real production code just delete the cookie. That works for the honest user, but if anyone has copied the JWT before logout, it's still valid until it expires naturally. Calling `token.revoke` puts it on the revocation list so it can't be used again, no matter who has it.

🛡️ **Mitigation in action: Token Theft (Part 1, vector 10)**

Refresh rotation plus revocation on logout closes the last gap from Part 2. Now if a token leaks, we have a way to kill it.

## Step 6. RegistrationsController

Create `app/controllers/api/v1/registrations_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class RegistrationsController < BaseController
      skip_before_action :doorkeeper_authorize!

      def create
        user = User.new(user_params)

        if user.save
          render json: { message: "Account created successfully" }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def skip_authorization?
        true
      end

      def user_params
        params.require(:user).permit(:email, :password, :password_confirmation)
      end
    end
  end
end
```

The interesting line is `user_params`. It explicitly lists which fields are allowed: email, password, password_confirmation. Nothing else. If a clever user POSTs `{ "user": { "email": "...", "password": "...", "admin": true, "role": "superuser" } }`, those extra fields are silently dropped.

🛡️ **Mitigation in action: Mass Assignment (Part 1, vector 7)**

This is the OWASP "mass assignment" vector. Strong params is Rails' built-in fix. The rule I follow: every controller that takes user input has a `*_params` method, and that method whitelists only the fields it expects. Never use `params[:user]` directly to build a record. Ever.

Notice also that on success we don't echo back the user's data. Just a message. That keeps us from accidentally returning fields we never meant to expose.

🛡️ **Mitigation in action: Excessive Data Exposure (Part 1, vector 8)**

Same idea on the way out. We'll formalize this with serializers later (probably `alba` because it's fast and dependency-free), but for now the rule is: build the response hash by hand, listing exactly which fields go out.

## Step 7. UsersController and the `me` endpoint

The frontend needs a way to ask "am I logged in, and if so, who am I?" on page load. That's the classic `me` endpoint.

Create `app/controllers/api/v1/users_controller.rb`:

```ruby
# frozen_string_literal: true

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
```

Same pattern as before: hand-built response hash, only the fields we want to expose. `encrypted_password`, `sign_in_count`, `reset_password_token`, none of that should leak out, and with this pattern it can't.

## Step 8. Wire up the routes

Open `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  use_doorkeeper do
    skip_controllers :authorizations, :applications,
                     :authorized_applications, :tokens
  end

  namespace :api do
    namespace :v1 do
      post   'auth/register', to: 'registrations#create'
      post   'auth/login',    to: 'sessions#create'
      delete 'auth/logout',   to: 'sessions#destroy'
      post   'auth/refresh',  to: 'sessions#refresh'

      get 'me', to: 'users#me'
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

The `skip_controllers` block on Doorkeeper is important. Out of the box, Doorkeeper mounts a bunch of OAuth2 endpoints (authorization page, application management, etc) that are designed for the browser-based OAuth flow. We don't need any of that, so we strip it out. Less code on the public internet means less attack surface.

Here's the API at a glance:

| Method | Endpoint | Description | Auth required |
|--------|----------|-------------|---------------|
| POST | `/api/v1/auth/register` | Create new account | No |
| POST | `/api/v1/auth/login` | Login, sets cookies | No |
| DELETE | `/api/v1/auth/logout` | Revoke tokens, clear cookies | Yes |
| POST | `/api/v1/auth/refresh` | Refresh access token | Cookie only |
| GET | `/api/v1/me` | Current user data | Yes |

## Step 9. Test with curl

The trick when testing cookie-based auth with curl is the `-c` and `-b` flags. `-c cookies.txt` saves the cookies the server returns, `-b cookies.txt` sends them on the next request. It's basically what the browser does for you.

Register:

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"user": {"email": "me@example.com", "password": "s3cr3tP@ss", "password_confirmation": "s3cr3tP@ss"}}'
```

Login (saves cookies):

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -c cookies.txt \
  -d '{"email": "me@example.com", "password": "s3cr3tP@ss"}'
```

Me (protected, sends cookies):

```bash
curl http://localhost:3000/api/v1/me -b cookies.txt
```

Refresh:

```bash
curl -X POST http://localhost:3000/api/v1/auth/refresh \
  -b cookies.txt -c cookies.txt
```

Logout:

```bash
curl -X DELETE http://localhost:3000/api/v1/auth/logout -b cookies.txt
```

If all five of those work, your auth flow is alive. But we're not done. An attacker right now can hit `/login` ten thousand times per second with different passwords. Let's fix that.

## Step 10. Rate limiting with Rack-Attack

Rack-Attack sits in the middleware stack and inspects every request before it reaches your controllers. It can throttle, block, or safelist IPs based on rules you define. It's stupidly simple to set up and saves you from a lot of pain.

Add it to your Gemfile:

```ruby
# Security
# ...
gem 'rack-attack'
```

Then `bundle install`.

Create `config/initializers/rack_attack.rb`:

```ruby
# frozen_string_literal: true

class Rack::Attack
  # Throttle login attempts by IP: max 5 per 20 seconds
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == '/api/v1/auth/login' && req.post?
  end

  # Throttle login attempts by email: max 5 per 20 seconds
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/api/v1/auth/login' && req.post?
      req.params['email'].to_s.downcase.gsub(/\s+/, "")
    end
  end

  # General API limit: 300 requests per IP per 5 minutes
  throttle('api/ip', limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?('/api')
  end

  # Custom response when throttled
  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: "Too many requests. Please slow down." }.to_json]
    ]
  end
end
```

Why throttle by both IP and email? An attacker with a botnet can rotate through thousands of IPs, and IP-only throttling won't catch them because each IP only sends a few requests. But all those requests are still targeting the same email, so the email-based throttle does catch them. The reverse is also true: a single attacker hammering many different accounts from one IP gets caught by the IP throttle. The two rules together cover both attack shapes.

🛡️ **Mitigation in action: Brute Force (Part 1, vector 4)**

Combined with bcrypt's slowness from Part 2, this makes online brute force impractical. Five attempts per 20 seconds means an attacker can try maybe 15 passwords per minute, per email. At that rate, even a weak password takes years to crack.

One gotcha I learned the hard way: in development, Rack-Attack defaults to using the memory store, which resets every time you restart the server. That's fine. But in production you almost certainly want to point it at Redis, otherwise each app server has its own counter and an attacker can bypass the limit by spreading requests across servers. I'll show that config when we deploy in a later part.

## Step 11. HTTP security headers with secure_headers

The browser will enforce a bunch of security policies for you, but only if you tell it to. The `secure_headers` gem makes that easy.

Add it to the Gemfile:

```ruby
gem 'secure_headers'
```

`bundle install`, then create `config/initializers/secure_headers.rb`:

```ruby
SecureHeaders::Configuration.default do |config|
  # Force HTTPS for 1 year
  config.hsts = "max-age=31536000; includeSubDomains"

  # Restrict what resources can load
  config.csp = {
    default_src: %w['self'],
    script_src: %w['self'],
    connect_src: %w['self']
  }

  # Prevent your site from being framed (clickjacking)
  config.x_frame_options = "DENY"

  # Stop MIME type sniffing
  config.x_content_type_options = "nosniff"

  # Legacy XSS filter (still useful for older browsers)
  config.x_xss_protection = "1; mode=block"

  # Don't leak full URLs in the Referer header
  config.referrer_policy = "strict-origin-when-cross-origin"
end
```

Quick tour of what each header does:

* **HSTS** tells browsers "for the next year, never talk to this domain over plain HTTP". This shuts down SSL stripping attacks, where an attacker on the same Wi-Fi downgrades your connection to HTTP.
* **X-Frame-Options: DENY** stops other sites from loading yours in an iframe, which is the foundation of clickjacking attacks.
* **X-Content-Type-Options: nosniff** stops browsers from guessing the content type of a response, which has historically been used to execute scripts that were uploaded as "images".
* **CSP** is the big one. It tells the browser exactly which sources of scripts, styles, and connections are allowed. Our config here is very strict ("self" only), which is appropriate for a pure API. If you're serving HTML too, you'll need to relax it.

🛡️ **Mitigation in action: MITM (Part 1, vector 9)**

HSTS plus `secure: true` on cookies (set in Part 2) is the one-two punch against MITM attacks. Combined with `force_ssl` in production (coming in Part 4), there's no way for an attacker on your network to downgrade the connection.

## Step 12. Encrypt sensitive fields with Lockbox

bcrypt protects passwords because it's a one-way hash, you never need to read the original. But what about fields you DO need to read, like phone numbers, addresses, or government IDs? You can't hash those. You need to encrypt them, so the database stores ciphertext and the app decrypts it in memory when needed.

That's what Lockbox does.

Add to the Gemfile:

```ruby
# Encryption
gem 'lockbox'
```

`bundle install`. Then generate a master key:

```bash
bin/rails runner "puts Lockbox.generate_key"
```

Take the output and store it in your Rails credentials (`bin/rails credentials:edit`):

```yaml
lockbox_master_key: <paste the generated key here>
```

Create `config/initializers/lockbox.rb`:

```ruby
Lockbox.master_key = Rails.application.credentials.lockbox_master_key
```

Now in any model, you can mark fields as encrypted. For example, if we added a phone column to User:

```ruby
class User < ApplicationRecord
  encrypts :phone

  # If you need to search by encrypted field, use blind_index
  blind_index :phone
end
```

The migration would look like:

```bash
bin/rails generate migration AddEncryptedPhoneToUsers
```

```ruby
add_column :users, :phone_ciphertext, :text
add_column :users, :phone_bidx, :text  # for blind_index searching
```

Then `bin/rails db:migrate`.

`encrypts :phone` means the value is encrypted before INSERT and decrypted on read. The database column is literally named `phone_ciphertext` and contains base64 ciphertext. If someone dumps your database, they see nothing.

`blind_index` is a clever workaround for the obvious problem with encrypted fields: you can't search them, because two encryptions of the same value produce different ciphertext. The blind index is a deterministic hash of the value, stored separately, which you can search on. It's not as private as the encryption itself, but it lets `User.where(phone: "...")` actually find records.

I'm not adding a phone field in this tutorial because we don't need one yet, but I wanted to show the pattern so you can apply it when you do add sensitive fields. Personal rule of thumb: any field that would be embarrassing or harmful if it leaked, encrypt it.

## Step 13. Structured logs with Lograge

Rails' default log format is fine for development but painful in production. You get six lines per request, none of them parseable as structured data, and no consistent fields. Lograge condenses each request to a single structured line that you can ship to Datadog, Loki, CloudWatch, or whatever you use.

Add to the Gemfile:

```ruby
# Monitoring & Logging
gem 'lograge'
```

`bundle install`. Then create `config/initializers/lograge.rb`:

```ruby
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
```

To get `user_id` into logs, you'll want to append it to the payload from `ApplicationController`:

```ruby
def append_info_to_payload(payload)
  super
  payload[:host]    = request.host
  payload[:user_id] = current_user&.id if doorkeeper_token
end
```

This is small but huge when you're debugging at 2 AM and trying to figure out which user's session caused that 500 error.

## Where we are right now

Five working auth endpoints, rate limiting, encrypted DB fields ready when you need them, hardened HTTP headers, and structured logs. The API is genuinely usable now, not just configured.

But we still have gaps. Most notably, we haven't done explicit CSRF tokens yet (the SameSite cookie helps but isn't enough on its own for state-changing endpoints), and we haven't tackled IDOR (insecure direct object references) which only becomes a problem once we have resources to reference. Both of those plus production error handling, `force_ssl`, and serializers are coming up.

## Progress tracker: security vectors from Part 1

| # | Attack vector | Status | Where |
|---|---------------|--------|-------|
| 1 | XSS | 🟢 Mostly mitigated | HttpOnly cookies (Part 2) + strict CSP headers (Step 11) |
| 2 | SQL Injection | 🟢 Mitigated by default | Active Record + strong params throughout controllers |
| 3 | CSRF | 🟡 Partially mitigated | SameSite cookies + pinned CORS origins. Explicit CSRF tokens still pending. Part 4. |
| 4 | Brute Force | 🟢 Mitigated | bcrypt + Rack-Attack IP and email throttles (Step 10) |
| 5 | User Enumeration | 🟢 Mitigated | Generic "Invalid credentials" message (Step 5) |
| 6 | IDOR | 🔴 Not yet | Will be addressed with Pundit policies + Sqids. Part 5. |
| 7 | Mass Assignment | 🟢 Mitigated | Strong params in every controller (Step 6) |
| 8 | Excessive Data Exposure | 🟡 Partially mitigated | Hand-built response hashes. Formal serializers in Part 4. |
| 9 | MITM | 🟢 Mostly mitigated | HSTS (Step 11) + secure cookies. `force_ssl` in Part 4. |
| 10 | Token Theft | 🟢 Mitigated | HttpOnly + encrypted cookies + short tokens + rotation + revocation on logout |
| 11 | Verbose Error Messages | 🟡 Partially mitigated | Generic 403/404 responses (Step 4). Production rescue handler in Part 4. |

Legend: 🟢 Covered, 🟡 Partial, 🔴 Pending

## Coming up in Part 4

We finish the security checklist. CSRF tokens for the endpoints that need them, `force_ssl` and the production error handler, and we'll introduce a serializer library so we stop hand-rolling response hashes in every action. After that we'll be ready to start adding actual resources (and the IDOR mitigation that comes with them) in Part 5.

If this helped, follow along so you catch the next one. And if anything broke or didn't make sense, drop a comment, I read all of them.
