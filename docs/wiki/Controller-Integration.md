# Controller Integration

## Including the Trane controller mixin

Trane ships the controller mixin in two pieces:

- `Trane::Controller::Renderer` — adds `render contract: data` support.
- `Trane::Controller::ErrorHandler` — captures `StandardError` subclasses
  and maps them to registered Trane errors.

The convenience `Trane::Controller` includes both. **Include it only in
API-specific base controllers**:

```ruby
# app/controllers/api/base_controller.rb
class Api::BaseController < ActionController::API
  include Trane::Controller
end
```

If your app mixes HTML and JSON, DO NOT include `Trane::Controller` in an
`ApplicationController < ActionController::Base` — the `rescue_from
StandardError` would intercept exceptions Devise / Pundit / etc. expect to
bubble up. Instead, include selectively:

```ruby
class Api::BaseController < ActionController::API
  include Trane::Controller::Renderer
  include Trane::Controller::ErrorHandler
end

class ApplicationController < ActionController::Base
  # No Trane mixins here
end
```

### Caveat: `prepend`-vs-`include` ordering

If your controller `prepend`s its own `#render` (e.g., for tracing or
logging), it runs BEFORE `Trane::Controller::Renderer`. Chain via `super`
to reach the Trane implementation.

This provides:

1. **`render contract:`** — contract-based response rendering.
2. **Automatic error handling** — `rescue_from StandardError` with structured JSON responses (see [Error Handling](Error-Handling.md)).

## Rendering responses

Use `render contract:` passing a hash whose keys match the operation's
response field names:

```ruby
# For response: field :user, :user
render contract: { user: @user }

# For response: field :users, :array, of: :user
render contract: { users: @users }

# For response: field :message, :string
render contract: { message: "User deleted successfully" }

# With explicit status (for 201 Created, etc.)
render contract: { user: @user }, status: :created
```

## How status codes map to response definitions

Trane selects the response definition based on the HTTP status code:

```ruby
# Uses response 200 (default when no status: is passed)
render contract: { user: @user }

# Uses response 201
render contract: { user: @user }, status: :created

# Uses response 204
render contract: { message: "Done" }, status: :no_content
```

The operation must have a `response` block defined for the given status code,
otherwise Trane raises an error.

## Raising errors

Simply raise your exception classes. Trane handles the rest:

```ruby
def show
  @user = User.find(params[:id])
  render contract: { user: @user }
rescue ActiveRecord::RecordNotFound
  raise UserNotFound
end

def create
  @user = User.new(user_params)
  @user.save || raise(UserInvalid.new(@user.errors))
  render contract: { user: @user }, status: :created
end
```

## Controllers without contracts

If a route does not have `contract: { operation: ... }` declared, no contract
can be resolved for `render contract:` — and without a contract, the field
filtering that contracts exist for cannot run. By default this **raises
`Trane::Error`** with the exact fix in the message, instead of silently
serving the unfiltered object (which would expose every attribute — a model's
full `as_json` includes columns like `password_digest`).

Hosts that want the fallback behavior can opt in:

```ruby
Trane.configure do |config|
  config.on_missing_operation = :log       # serve unserialized, warn per request
  # config.on_missing_operation = :fallback # serve unserialized, silently
end
```
