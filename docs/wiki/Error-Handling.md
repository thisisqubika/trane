# Error Handling

The error catalog maps error keys to HTTP status codes and descriptions, and
`Trane::Controller::ErrorHandler` maps raised exceptions to catalog entries at
request time.

## File location

```
app/api_contract/errors.rb
```

## Registering errors

Trane maps raised exceptions to registered errors via their class name.
You can register by FQDN (recommended for namespaced errors) or short
name (recommended for top-level error classes):

```ruby
Trane.errors do
  # Top-level class. Short-name registration works because the class
  # has no namespace.
  error :UserNotFound, status_code: 404, description: "User not found"

  # Namespaced class — register by FQDN to avoid collisions with
  # other classes sharing the short name.
  error "Errors::ArtistNotFound", status_code: 404, description: "Artist not found"

  # Or pass the class directly (uses Class#name).
  error Errors::SongInvalid, status_code: 422, description: "Song is invalid"
end
```

`description:` is optional when you prefer to omit it.

## How error matching works

When an exception is raised in a controller:

1. Trane captures it via `rescue_from StandardError`.
2. It looks up the exception's **FQDN** (`exception.class.name`) in the error registry.
3. If not found, falls back to the exception's **short name** (`name.split("::").last`) for backward compatibility with top-level error registrations.
4. If found, it renders a structured JSON error response with the registered status code.
5. If neither matches, it renders a generic 500 response.

The same two-step resolution applies to operation `error_keys`: an operation
declaring `errors { key :UserNotFound }` matches either a short-name or FQDN
registration whose short name is `"UserNotFound"`.

## Exception class conventions

Your exception classes must have names that match the error registry keys:

```ruby
# app/errors/user_not_found.rb
class UserNotFound < StandardError
  def message = "User not found"
end

# app/errors/user_invalid.rb
class UserInvalid < StandardError
  def initialize(errors)
    super(errors.full_messages.join(", "))
  end
end
```

The key `:UserNotFound` matches the class `UserNotFound`. Namespaced
exceptions also work:

- If registered by FQDN (e.g., `"MyApp::UserNotFound"`), the FQDN must match exactly.
  An unrelated exception from another namespace with the same demodulized name
  (`SomeGem::UserNotFound`) does **not** match — it falls through to the
  generic 500 path.
- If registered by short name (e.g., `:UserNotFound`), any class whose last name segment is `"UserNotFound"` will match.

## Rails-reserved exceptions

Exceptions listed in `ActionDispatch::ExceptionWrapper.rescue_responses`
(e.g. `ActiveRecord::RecordNotFound` → 404,
`ActionController::ParameterMissing` → 400) are re-raised when no Trane error
is registered for them, so Rails' exception middleware applies its default
status mapping. Keep `config.consider_all_requests_local = false` in
production so those re-raised exceptions serve the static `public/404.html` /
`500.html` pages.

Hosts that want to swallow these into the Trane envelope can register them
explicitly (`Trane.errors { error "ActiveRecord::RecordNotFound", ... }`); the
Trane lookup wins over the re-raise path.

An API that must answer JSON on *every* path can instead set
[`rescue_rails_reserved`](Configuration.md#response-envelopes) to `true`, which
swallows every reserved exception without registering each one by hand. It
costs two things, both documented there: the exception loses its native status
and comes back as a plain 500, and Rails' exception middleware stops seeing it,
so Trane reports it instead — same event count, longer log line. Registering
the exception explicitly is the option that keeps its status.

## Error response format

This is the **default** structure every error response follows:

```json
{
  "errors": [
    {
      "key": "UserNotFound",
      "message": "User not found"
    }
  ]
}
```

The `message` field is populated from the exception's `.message` method.

A host serving a pre-existing contract can replace this shape entirely with
[`error_envelope`](Configuration.md#response-envelopes) — a callable receiving
the exception and its resolved definition, returning whatever body that
contract requires. Everything below about matching, statuses and the unhandled
path is unaffected by that choice: the envelope decides the body, never the
status.

> **Security note:** a registered error's `message` reaches the client in
> **every** environment, production included. Framework and library exception
> messages are written for logs and may reveal internals — e.g.
> `ActiveRecord::RecordNotFound#message` includes the model name and lookup
> conditions. Prefer the pattern shown above (rescue the framework exception,
> raise a domain error with a curated message); register framework exceptions
> directly only when their messages are acceptable to expose.

## Unhandled errors

Exceptions not in the registry return a 500 response. The **default** envelope
gates what that response says by environment:

- **Development/Test** (`Rails.env.local?`): includes the exception class and message for debugging.
- **Any other environment** (production, staging, uat, ...): returns a generic
  `"An unexpected error occurred"` message. Custom environments are protected
  by default — exception messages can carry SQL, record values, or internal
  hostnames, and this handler renders before Rails' exception middleware, so
  `consider_all_requests_local` cannot cover these responses.

A custom [`error_envelope`](Configuration.md#response-envelopes) receives that
same exception with a `nil` definition and decides the body itself, so it opts
out of this gating — a host echoing `exception.message` there is choosing to
expose it everywhere, and should mean it. The 500 status is not the envelope's
to change.

Before rendering the envelope, the exception is **reported and logged**:
through `Rails.error.report(exception, handled: true, source: "trane")` (the
`ActiveSupport::ErrorReporter` interface error trackers like Sentry subscribe
to) and as a `Rails.logger.error` line with class, message, and backtrace.
Without this, `rescue_from` would swallow the exception before Rails'
exception-reporting middleware could see it, and production 500s would leave
no trace in logs or error trackers.
