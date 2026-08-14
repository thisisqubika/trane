# Trane

[![CI](https://github.com/thisisqubika/sunga/actions/workflows/ci.yml/badge.svg)](https://github.com/thisisqubika/sunga/actions/workflows/ci.yml)

Contract enforcement and documentation layer for Rails APIs.

Trane enforces structured JSON responses, provides deterministic serialization via contract-based representations, captures errors globally, and publishes API documentation (HTML + JSON).

---

## Table of Contents

- [Naming](#naming)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Representations](#representations)
- [Operations](#operations)
- [Error Definitions](#error-definitions)
- [Controller Integration](#controller-integration)
- [Routes](#routes)
- [Serialization](#serialization)
- [Extra Attributes (Optional Fields)](#extra-attributes-optional-fields)
- [Strict Contract Validation](#strict-contract-validation)
- [Boot-time Validation](#boot-time-validation)
- [Documentation Endpoints](#documentation-endpoints)
- [File Structure Conventions](#file-structure-conventions)
- [Field Types Reference](#field-types-reference)
- [Complete Example](#complete-example)
- [Testing](#testing)

---

## Naming

**Trane** is named after John Coltrane.

The name also reads as **train**, a fitting companion for a gem that runs entirely on **Rails**.

Trane draws its inspiration from **Angus**, a predecessor gem named after Angus Young.

---

## Installation

Add Trane to your Gemfile. During development, reference it as a local path gem:

```ruby
gem "trane", path: "./trane"
```

Then run:

```bash
bundle install
```

Trane integrates with Rails via a Rails Engine. Mount it in your `config/routes.rb` to expose the documentation endpoints (see [Documentation Endpoints](#documentation-endpoints)).

---

## Supported versions

| Component | Versions |
|---|---|
| Ruby | >= 3.2 |
| Rails | 7.2, 8.0, 8.1 |

Trane's CI matrix runs gem specs against each supported Rails minor.
The host app's tests run against the latest Rails minor.

---

## Quick Start

### 1. Configure the gem

```ruby
# config/initializers/trane.rb
Trane.configure do |config|
  config.strict_mode = nil   # nil (auto-detect), :raise, :log, or :ignore
end
```

### 2. Define error catalog

```ruby
# app/api_contract/errors.rb
Trane.errors do
  error :UserNotFound, status_code: 404, description: "User not found"
  error :UserInvalid,  status_code: 422, description: "User is invalid"
end
```

### 3. Define a representation

```ruby
# app/api_contract/representations/user.rb
Trane.representation :user do
  field :id,    type: :integer
  field :name,  type: :string
  field :email, type: :string
end
```

### 4. Define an operation

```ruby
# app/api_contract/operations/users.rb
Trane.operation :get_user do
  summary "Get a user by id"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
  end
end
```

### 5. Include the controller concern

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Trane::Controller
end
```

### 6. Use `render contract:` in your controller

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    render contract: { user: @user }
  rescue ActiveRecord::RecordNotFound
    raise UserNotFound
  end
end
```

### 7. Add route metadata

```ruby
# config/routes.rb
get "/users/:id", to: "users#show", contract: { operation: :get_user }
```

That's it. Trane will serialize the response according to the contract and handle errors. To enable documentation, mount the engine in `config/routes.rb` (see [Documentation Endpoints](#documentation-endpoints)).

---

## Configuration

Configure Trane in an initializer:

```ruby
# config/initializers/trane.rb
Trane.configure do |config|
  config.strict_mode          = nil     # nil (auto-detect), :raise, :log, or :ignore
  config.on_missing_operation = :raise  # :raise, :log, or :fallback
end
```

### Options

| Option | Default | Description |
|---|---|---|
| `strict_mode` | `nil` | Controls response contract validation behavior. |
| `on_missing_operation` | `:raise` | What `render contract:` does when the route declared no `contract:` — see [Controllers without contracts](#controllers-without-contracts). |

The API name is **not** configurable. The docs descriptor publishes
`Rails.application.name` as `service.name` (`SungaDemo::Application` →
`"sunga-demo"`). Route prefixes are the host's decision: scope your routes and
mount the docs engine wherever you want — interpolating
`Rails.application.name` keeps both in sync with the descriptor.

### Strict Mode

When `strict_mode` is `nil`, it auto-detects based on Rails environment:

| Environment | Behavior |
|---|---|
| `development` | `:raise` — raises `Trane::ContractViolation` |
| `test` | `:raise` — raises `Trane::ContractViolation` |
| `production` | `:log` — logs a warning via `Rails.logger.warn` |

You can override this explicitly:

```ruby
config.strict_mode = :raise   # Always raise on contract violations
config.strict_mode = :log     # Always log warnings
config.strict_mode = :ignore  # Skip validation entirely
```

### Custom Contract Paths

By default, Trane loads contract files from `app/api_contract/` relative to the Rails application root. To use a different location — or multiple locations — set `contracts_paths` in `config/application.rb`:

```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    config.trane.contracts_paths = ["app/contracts", "engines/billing/app/contracts"]
  end
end
```

**Timing requirement**: this setting must be in `config/application.rb`, NOT in `config/initializers/trane.rb`. The Engine's `trane.ignore_autoload_paths` initializer runs before config initializers are loaded; by the time `config/initializers/trane.rb` is evaluated, the autoload ignore step has already passed and Zeitwerk will attempt to eager-load the contract files.

**Validation**: each entry must be a non-blank String or Pathname without glob characters. An empty array or a non-array value raises `Trane::Error` at boot.

**Loading order across multiple paths** follows two phases:
1. Every `errors.rb` from each base path is loaded first (in declaration order).
2. All other `.rb` files from each base path are loaded next (sorted within each path).

This guarantees that error registrations from any path are available when operations from any other path reference them.

### Configuration lifecycle and freezing

`Trane::Configuration` is frozen once, at boot, before Rails draws routes — but
that ordering is incidental, not a dependency: route drawing never reads
`Trane::Configuration` at all (the API name is `Rails.application.name`, and
`strict_mode` is read only when a response is rendered). The freeze exists to
prevent post-boot mutation in multi-threaded servers (Puma, Falcon). The
expected lifecycle is:

1. `config/initializers/trane.rb` sets `strict_mode`.
2. The Engine initializer `trane.freeze_configuration` (runs after `:load_config_initializers`, before Rails' Finisher batch) freezes the configuration.
3. Rails' Finisher batch draws routes.

#### Testing with a different configuration

Use `Trane::Testing.with_configuration` to temporarily reconfigure, run a block, then restore:

```ruby
require "trane/testing"

Trane::Testing.with_configuration(strict_mode: :ignore) do |config|
  # config is frozen inside the block, exactly as it is after boot.
  # Response contract violations are skipped instead of raising.
  get "/api/users"
  expect(last_response.status).to eq(200)
end
# Configuration is restored to its prior state after the block.
```

The helper does not touch the route set: `strict_mode` is read when a response is
rendered, never when routes are drawn.

`with_configuration` is opt-in — it is not loaded by default. Add `require "trane/testing"` to your test helper or individual spec file.

The helper:
1. Snapshots the current configuration values (`strict_mode` and
   `contracts_paths`) and frozen state.
2. Calls `reset!`, applies the given attributes, and calls `freeze!`.
3. Yields the configuration to the block.
4. Restores the snapshot — even if the block raises. Because `reset!` also
   clears `contracts_paths`, that value is snapshotted and restored too, even
   though it is not among the attributes this helper's kwargs accept
   (`contracts_paths` is set via `config.trane.contracts_paths` in
   `config/application.rb`, not via `Trane.configure`).

---

## Representations

Representations define the shape of serializable objects. They are declarative schemas — no Ruby logic, just field definitions.

### File location

```
app/api_contract/representations/*.rb
```

### Basic representation

```ruby
Trane.representation :user do
  field :id,         type: :integer
  field :name,       type: :string
  field :email,      type: :string
  field :created_at, type: :datetime, format: :iso8601
end
```

### Fields with format

The `format:` option controls how values are serialized. Currently supported:

```ruby
field :birthday,   type: :date,     format: :iso8601   # calls .iso8601 → "1990-05-15"
field :created_at, type: :datetime, format: :iso8601   # calls .iso8601 → "2026-04-15T12:00:00+00:00"
```

When `format: :iso8601` is set, Trane calls `.iso8601` on the value. If the value does not respond to `.iso8601`, it is passed through unchanged.

### Extra fields (optional)

Fields marked `extra: true` are excluded from responses by default. Clients must explicitly request them via the `extra_attributes[]` query parameter (see [Extra Attributes](#extra-attributes-optional-fields)).

```ruby
Trane.representation :user do
  field :id,       type: :integer
  field :name,     type: :string
  field :nickname, type: :string, extra: true    # excluded unless requested
  field :bio,      type: :string, extra: true    # excluded unless requested
end
```

### Array fields

```ruby
Trane.representation :user do
  field :id,      type: :integer
  field :hobbies, type: :array, of: :string     # array of primitives
  field :pets,    type: :array, of: :pet        # array of representations
end
```

### Representation references

A field can reference another representation by name:

```ruby
Trane.representation :address do
  field :street, type: :string
  field :city,   type: :string
end

Trane.representation :user do
  field :id,      type: :integer
  field :name,    type: :string
  field :address, type: :address    # references the :address representation
end
```

This creates nested serialization: the `:address` field will be serialized according to the `:address` representation.

Representations can be defined in any order — references are resolved at serialization time, not at definition time.

### Object passthrough (variable structure)

For fields whose structure is not known at definition time, use `:object` without a block:

```ruby
Trane.representation :event do
  field :type,    type: :string
  field :payload, type: :object     # passed through as-is, no serialization
end
```

`:object` has two distinct uses:

- **With a block** — declares an inline nested structure; only the declared child fields are serialized.
- **Without a block** — acts as a passthrough; the value is included in the response exactly as provided, with no transformation or recursive validation.

---

## Operations

Operations define the contract for an API endpoint: what it receives (request) and what it returns (response).

### File location

```
app/api_contract/operations/**/*.rb
```

Files can be nested in subdirectories for organization.

### Minimal operation

```ruby
Trane.operation :list_users do
  summary "List all users"

  response 200 do
    field :users, type: :array, of: :user
  end
end
```

### Operation with request parameters

```ruby
Trane.operation :get_user do
  summary "Get a user by id"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
  end
end
```

### Request DSL

The `request` block supports three kinds of parameters:

#### Path parameters

```ruby
request do
  path :id, type: :integer
  path :user_id, type: :integer
end
```

Path params are always required by definition (they're part of the URL). The `required:` option is not accepted — pass it and Trane raises an `ArgumentError`.

#### Query parameters

```ruby
request do
  query :page,     type: :integer, required: false
  query :per_page, type: :integer, required: false
  query :status,   type: :string,  required: false
end
```

`required:` defaults to `false` for query params.

#### Body schema

```ruby
request do
  body do
    field :user, required: true do
      field :name,      type: :string, required: true
      field :email,     type: :string, required: true
      field :last_name, type: :string
      field :birthday,  type: :date
    end
  end
end
```

Body fields accept `required:` (default `false`). It applies at any nesting level:
- On a leaf field: that field must be present in the request body.
- On a nested object (`field :user do ... end`): the object itself must be present (children are evaluated independently).

`required:` is **not accepted** in response fields or representations — passing it raises `ArgumentError`. For input contracts, see also `path` (always required, kwarg not accepted) and `query` (default `required: false`).

**Documentation only**: Trane does not yet validate that required body fields are present in incoming requests — this declaration affects the published JSON/HTML docs.

The body supports all field types including nested objects, arrays, and representation references:

```ruby
request do
  body do
    field :user, required: true do
      field :name,    type: :string, required: true
      field :hobbies, type: :array, of: :string
      field :pets, type: :array do
        field :name, type: :string
        field :type, type: :string
      end
      field :address do
        field :street, type: :string
        field :city,   type: :string
      end
    end
  end
end
```

### Response DSL

Define response schemas for specific HTTP status codes:

```ruby
Trane.operation :create_user do
  summary "Create a user"

  response 201 do
    field :user, type: :user
  end

  errors do
    key :UserInvalid
  end
end
```

An operation can have multiple response definitions:

```ruby
Trane.operation :update_user do
  response 200 do
    field :user, type: :user
  end

  response 204 do
    field :message, type: :string
  end
end
```

Response fields follow the same DSL as representation fields:

```ruby
response 200 do
  field :user,    type: :user                     # representation reference
  field :count,   type: :integer                  # primitive
  field :tags,    type: :array, of: :string       # array of primitives
  field :items,   type: :array, of: :item         # array of representations
  field :message, type: :string                   # simple string
  field :data,    type: :object                    # passthrough (no block = variable structure)
  field :result do                                # inline nested object
    field :score, type: :integer
    field :label, type: :string
  end
end
```

### Error keys

Operations declare which errors they may produce:

```ruby
errors do
  key :UserNotFound
  key :UserInvalid
end
```

Each key must correspond to an error defined in the error catalog (see [Error Definitions](#error-definitions)). This is validated at boot time.

---

## Error Definitions

The error catalog maps error keys to HTTP status codes and descriptions.

### File location

```
app/api_contract/errors.rb
```

### Registering errors

Trane maps raised exceptions to registered errors via their class name.
You can register by FQDN (recommended for namespaced errors) or short
name (legacy, recommended for top-level error classes):

```ruby
Trane.errors do
  # Top-level class (the demo pattern). Short-name registration works
  # because the class has no namespace.
  error :UserNotFound, status_code: 404, description: "User not found"

  # Namespaced class — register by FQDN to avoid collisions with
  # other classes sharing the short name.
  error "Errors::ArtistNotFound", status_code: 404, description: "Artist not found"

  # Or pass the class directly (uses Class#name).
  error Errors::SongInvalid, status_code: 422, description: "Song is invalid"
end
```

`description:` is optional when you prefer to omit it.

### How error matching works

When an exception is raised in a controller:

1. Trane captures it via `rescue_from StandardError`.
2. It looks up the exception's **FQDN** (`exception.class.name`) in the error registry.
3. If not found, falls back to the exception's **short name** (`name.split("::").last`) for backward compatibility with top-level error registrations.
4. If found, it renders a structured JSON error response with the registered status code.
5. If neither matches, it renders a generic 500 response.

The same two-step resolution applies to operation `error_keys`: an operation
declaring `errors { key :UserNotFound }` matches either a short-name or FQDN
registration whose short name is `"UserNotFound"`.

### Exception class conventions

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

The key `:UserNotFound` matches the class `UserNotFound`. Namespaced exceptions also work:
- If registered by FQDN (e.g., `"MyApp::UserNotFound"`), the FQDN must match exactly.
  An unrelated exception from another namespace with the same demodulized name
  (`SomeGem::UserNotFound`) does **not** match — it falls through to the
  generic 500 path.
- If registered by short name (e.g., `:UserNotFound`), any class whose last name segment is `"UserNotFound"` will match.

### Error response format

All error responses follow this structure:

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

> **Security note:** a registered error's `message` reaches the client in
> **every** environment, production included. Framework and library exception
> messages are written for logs and may reveal internals — e.g.
> `ActiveRecord::RecordNotFound#message` includes the model name and lookup
> conditions. Prefer the pattern shown above (rescue the framework exception,
> raise a domain error with a curated message); register framework exceptions
> directly only when their messages are acceptable to expose.

### Unhandled errors

Exceptions not in the registry return a 500 response:

- **Development/Test** (`Rails.env.local?`): includes the exception class and message for debugging.
- **Any other environment** (production, staging, uat, ...): returns a generic
  `"An unexpected error occurred"` message. Custom environments are protected
  by default — exception messages can carry SQL, record values, or internal
  hostnames, and this handler renders before Rails' exception middleware, so
  `consider_all_requests_local` cannot cover these responses.

---

## Controller Integration

### Including the Trane controller mixin

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

#### Caveat: `prepend`-vs-`include` ordering

If your controller `prepend`s its own `#render` (e.g., for tracing or
logging), it runs BEFORE `Trane::Controller::Renderer`. Chain via `super`
to reach the Trane implementation.

This provides:

1. **`render contract:`** — contract-based response rendering.
2. **Automatic error handling** — `rescue_from StandardError` with structured JSON responses.

### Rendering responses

Use `render contract:` passing a hash whose keys match the operation's response field names:

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

### How status codes map to response definitions

Trane selects the response definition based on the HTTP status code:

```ruby
# Uses response 200 (default when no status: is passed)
render contract: { user: @user }

# Uses response 201
render contract: { user: @user }, status: :created

# Uses response 204
render contract: { message: "Done" }, status: :no_content
```

The operation must have a `response` block defined for the given status code, otherwise Trane raises an error.

### Raising errors

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

### Controllers without contracts

If a route does not have `contract: { operation: ... }` declared, no contract
can be resolved for `render contract:` — and without a contract, the field
filtering that contracts exist for cannot run. By default this **raises
`Trane::Error`** with the exact fix in the message, instead of silently
serving the unfiltered object (which would expose every attribute — a model's
full `as_json` includes columns like `password_digest`).

Hosts that want the old fallback behavior can opt in:

```ruby
Trane.configure do |config|
  config.on_missing_operation = :log       # serve unserialized, warn per request
  # config.on_missing_operation = :fallback # serve unserialized, silently
end
```

---

## Routes

Routes associate Rails controller actions with Trane operations via the `contract:` keyword, passed like any other route option.

### Defining routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get    "/users",     to: "users#index",   contract: { operation: :list_users }
  post   "/users",     to: "users#create",  contract: { operation: :create_user }
  get    "/users/:id", to: "users#show",    contract: { operation: :get_user }
  match  "/users/:id", via: [:patch, :put], to: "users#update",  contract: { operation: :update_user }
  delete "/users/:id", to: "users#destroy", contract: { operation: :destroy_user }
end
```

### Nested resources

```ruby
get    "/users/:user_id/cars",     to: "cars#index",   contract: { operation: :list_user_cars }
post   "/users/:user_id/cars",     to: "cars#create",  contract: { operation: :create_car }
get    "/users/:user_id/cars/:id", to: "cars#show",    contract: { operation: :get_car }
match  "/users/:user_id/cars/:id", via: [:patch, :put], to: "cars#update",  contract: { operation: :update_car }
delete "/users/:user_id/cars/:id", to: "cars#destroy", contract: { operation: :destroy_car }
```

### Route prefix

Scoping is entirely up to you — use Rails' native `scope`, `namespace`, or no prefix at all:

```ruby
Rails.application.routes.draw do
  scope "/myapi/api" do
    get "/users",     to: "users#index", contract: { operation: :list_users }
    get "/users/:id", to: "users#show",  contract: { operation: :get_user }
  end
end
```

### How it works

`Trane::RoutingExtension` is prepended onto `ActionDispatch::Routing::Mapper` process-globally by the Engine initializer `trane.prepend_routing_extension`, so `contract:` is available in every `routes.draw` block regardless of scoping. It stores the operation name in the route's defaults as `_trane_operation` and sets `as:` to the operation name (unless the caller already set one) so it shows up as the Prefix in `bin/rails routes`. At request time, the controller reads `_trane_operation` to determine which operation definition to use. Routes without `contract:` pass through unchanged.

---

## Serialization

### How objects are serialized

When you call `render contract: { user: @user }`, Trane:

1. Looks up the operation for the current route.
2. Selects the response definition matching the HTTP status code.
3. For each field in the response definition:
   - Extracts the value from the data hash.
   - If the field references a representation, recursively serializes using that representation's fields.
   - If the field is an array, serializes each element.
   - If the field has children (inline nested object), serializes recursively.
   - Applies format transformations (e.g., `iso8601`).
   - Skips `extra: true` fields unless requested.

### Value extraction

Trane supports both Hash data and objects:

```ruby
# Hash with symbol keys
render contract: { message: "Hello" }

# Hash with string keys (also works)
render contract: { "message" => "Hello" }

# ActiveRecord objects (reads attributes via public methods)
render contract: { user: @user }  # calls @user.id, @user.name, etc.

# Structs, Data objects, POROs — anything with public methods
render contract: { user: my_struct }
```

For Hash data, Trane tries the symbol key first, then the string key. For objects, it calls `public_send(field_name)`. If the method doesn't exist, `nil` is returned.

### Nil handling

Fields with `nil` values are always included in the response as JSON `null`:

```json
{
  "user": {
    "id": 1,
    "name": "Alice",
    "birthday": null,
    "created_at": null
  }
}
```

This ensures the response shape is always predictable and matches the contract.

### Nested serialization example

Given these definitions:

```ruby
Trane.representation :address do
  field :street, type: :string
  field :city,   type: :string
end

Trane.representation :user do
  field :id,      type: :integer
  field :name,    type: :string
  field :address, type: :address
end
```

And this render call:

```ruby
render contract: { user: @user }
```

Trane produces:

```json
{
  "user": {
    "id": 1,
    "name": "Alice",
    "address": {
      "street": "123 Main St",
      "city": "Springfield"
    }
  }
}
```

---

## Extra Attributes (Optional Fields)

Fields marked with `extra: true` are excluded from responses by default. Clients request them via the `extra_attributes[]` query parameter using dot-notation paths.

### Defining extra fields

```ruby
Trane.representation :user do
  field :id,       type: :integer
  field :name,     type: :string
  field :nickname, type: :string, extra: true
  field :bio,      type: :string, extra: true
end
```

### Requesting extra fields

Clients include the `extra_attributes[]` query parameter with dot-notation paths:

```
GET /users/1?extra_attributes[]=user.nickname
GET /users/1?extra_attributes[]=user.nickname&extra_attributes[]=user.bio
```

> **Security note:** `extra: true` controls default payload visibility, **not
> authorization**. Any client that can reach the endpoint can request any
> declared extra field (and the docs endpoint advertises which fields are
> extra). If a field requires authorization, enforce it in the controller —
> e.g. filter `params[:extra_attributes]` in a `before_action`, or don't pass
> the sensitive data to `render contract:` for unauthorized callers — or don't
> declare the field in the contract at all.

### Path construction

The dot-notation path is constructed from the response field hierarchy:

```
response field :user (type :user)
  └── representation field :nickname (extra: true)
      path: "user.nickname"
```

For arrays, the path applies to all elements:

```
GET /users?extra_attributes[]=users.nickname
```

This includes `nickname` for every user in the array.

### Nested extra fields

Extra fields work at any nesting depth:

```ruby
Trane.representation :address do
  field :street,   type: :string
  field :city,     type: :string
  field :zip_code, type: :string, extra: true
end

Trane.representation :user do
  field :name,    type: :string
  field :address, type: :address
  field :alias,   type: :string, extra: true
end
```

Request both:

```
GET /users/1?extra_attributes[]=user.alias&extra_attributes[]=user.address.zip_code
```

### Default response (no extra_attributes)

```json
{
  "user": {
    "name": "Alice",
    "address": {
      "street": "123 Main St",
      "city": "Springfield"
    }
  }
}
```

### Response with extra_attributes

```
GET /users/1?extra_attributes[]=user.alias&extra_attributes[]=user.address.zip_code
```

```json
{
  "user": {
    "name": "Alice",
    "alias": "Ali",
    "address": {
      "street": "123 Main St",
      "city": "Springfield",
      "zip_code": "62704"
    }
  }
}
```

---

## Strict Contract Validation

Strict validation checks that serialized responses match the declared contract. It runs after serialization and before the response is sent.

### What it checks

1. **Missing fields**: All non-extra declared fields must be present in the serialized result.
2. **Undeclared fields**: No keys in the result that aren't declared in the response definition.
3. **Nested validation**: Recursively validates fields that reference representations.

### Modes

| Mode | Behavior |
|---|---|
| `:raise` | Raises `Trane::ContractViolation` with all violations listed. |
| `:log` | Logs all violations via `Rails.logger.warn`. Response is still sent. |
| `:ignore` | Skips validation entirely. |

**Operational note on `:log`:** violations are logged once per response, with no
deduplication or rate-limiting — a broken contract on a high-traffic endpoint
logs a multi-line warning for every request until it is fixed. If that volume
is a concern, rely on your log pipeline's rate-limiting/alerting rather than
silencing Trane (`:ignore` also disables detection).

### Configuration

```ruby
Trane.configure do |config|
  config.strict_mode = :raise   # explicit mode
  config.strict_mode = nil      # auto-detect (default)
end
```

### Auto-detection

| Environment | Mode |
|---|---|
| `development` | `:raise` |
| `test` | `:raise` |
| `production` | `:log` |

### Error messages

When a violation occurs in `:raise` mode:

```
Trane::ContractViolation: Trane contract violations:
  count: missing from response
  user.email: missing from response
  extra_field: undeclared field in response
```

### Object type (passthrough)

Fields with `:object` type and no block are never recursively validated. Their values are accepted as-is.

---

## Boot-time Validation

Trane validates the referential integrity of all contract definitions when the Rails app boots (and on every code reload in development).

### What it checks

1. **Representation references**: Every field in an operation's response that references a representation (e.g., `field :user, :user`) must have a corresponding `Trane.representation :user` defined.

2. **Array element types**: Every `field :items, :array, of: :item` must have the `:item` representation defined (if it's not a primitive type).

3. **Error key references**: Every `key :ErrorName` in an operation's `errors` block must have a corresponding entry in `Trane.errors`.

### When it runs

Validation is gated on `config.eager_load`. It only runs when the host application
has `config.eager_load = true`.

- **Production**: validation runs at boot. A broken contract crashes startup — the
  correct behavior to surface contract drift before serving traffic.
- **Test** (`config.eager_load = ENV["CI"].present?` by default): validation runs in CI.
- **Development & `bin/rails console` / `rake`**: validation is skipped so a
  partially-broken contract doesn't block dev tooling.

To run validation explicitly (CI, ad-hoc verification, pre-deploy check):

```bash
bin/rails trane:check
```

This works in any environment and exits non-zero on the first validation error.

### Error messages

If validation fails, the app won't boot:

```
Trane::Error: Trane boot validation failed:
  operation :get_user response 200: field :user references representation :user, which does not exist
  operation :list_users response 200: field :users has array of :user, which does not exist as a representation
  operation :get_user references error :UserNotFound, but no such error is registered
```

### Primitive types are not validated

Fields with primitive types (`:string`, `:integer`, `:date`, `:object`, etc.) are not checked against the representation registry.

### Route contract validation

The `contract: { operation: :name }` metadata on routes is validated so typos fail loud
instead of silently bypassing the contract or surfacing only when a request hits the route.
Both checks raise `Trane::RoutingContractError` (a subclass of `Trane::Error`).

**A. `contract:` hash shape** — runs whenever a route is drawn (boot, and `bin/rails routes`
in development). The only accepted key is `:operation`; it must be present and non-blank.

```ruby
get "/users/:id", to: "users#show", contract: { operaton: :get_user }
# Trane::RoutingContractError: Unknown key `operaton` in contract:. Did you mean `operation`?

get "/users/:id", to: "users#show", contract: {}
# Trane::RoutingContractError: contract: requires a non-empty :operation
```

**B. Route → registry cross-check** — every route whose `contract:` names an operation must
reference one that is actually registered. Gated on `config.eager_load` like the contract
checks above (runs at boot in production/CI, skipped in development), and always run by
`bin/rails trane:check`:

```
Trane::RoutingContractError: Trane route/registry cross-check failed:
  GET /sunga-demo/api/artists/:id(.:format) references operation :get_artistt, but no such operation is registered (did you mean :get_artist?)
```

**Known limitation** — a typo in the `contract` *key itself* (e.g. `contractt: { operation: :get_user }`)
cannot be detected: Trane's routing extension never sees the misspelled key, so the route is
indistinguishable from one that legitimately declares no contract (like `/up`). Such a route
silently loses its contract. Spell the key `contract` carefully.

### Registry concurrency model

`Trane::Registry` exposes a single frozen snapshot via `Registry.operations`,
`.representations`, and `.errors`. Reads are lock-free.

Reload paths (`config.to_prepare` in the Engine, integration test setup) use
`Registry.replace! do |builder| ... end` to build a new snapshot atomically;
readers in other threads see either the prior or the new snapshot, never a
partially-rebuilt state. If the block raises, the prior snapshot is preserved
unchanged.

Direct `Registry.register_*` calls outside `replace!` still work (used by unit
specs); each call allocates a new snapshot via copy-on-write.

### Configuration lifecycle

`Trane.configure` is intended to be called **once** during boot, typically in
`config/initializers/trane.rb`. After all initializers run, `Trane::Configuration`
is **frozen** — any further attempt to set `strict_mode`
raises `FrozenError`. This guarantees running requests observe a consistent
configuration in multi-threaded environments (Puma, Falcon).

To reset between tests, call `Trane.reset!` — it empties the registry, clears
the configuration (values and frozen flag), and invalidates the docs cache in
one call. `Trane.configuration.reset!` (or the shim
`Trane::Configuration.instance.reset!`) is still available to reset only the
configuration.

### Process-level state

Trane keeps a single registry (operations, representations, errors) and a
single configuration per Ruby process, following the standard Rails model of
one application per process. Running multiple `Rails::Application` instances
in one process is not supported.

The public DSL (`Trane.operation`, `Trane.representation`, `Trane.errors`,
`Trane.configure`) and the lookup helpers (`Trane.registry`,
`Trane.configuration`) all address that process-level state. Registrations
made before Rails boots (e.g. in unit specs that never load Rails) land in
the same registry the booted application uses.

#### Backwards compatibility

The legacy module-level API still works:

```ruby
Trane::Registry.operations           # same as Trane.registry.operations
Trane::Configuration.instance.reset! # same as Trane.configuration.reset!
```

Both forms delegate to the process-level state.

---

## Documentation Endpoints

Trane ships a Rails Engine that serves the auto-generated documentation
(HTML + JSON). Mount it explicitly in your host's `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  # ... your API routes ...

  mount Trane::Engine, at: "/<your-api-name>/docs"
end
```

For example:

```ruby
mount Trane::Engine, at: "/sunga-demo/docs"
```

After mounting:

- `GET /sunga-demo/docs` → interactive HTML documentation
- `GET /sunga-demo/docs.json` → machine-readable Service Definition JSON

The mount path is host-controlled. You can wrap it in `constraints:` (e.g. for
authentication) or omit it entirely in environments where you don't want docs
exposed (e.g. production).

### Caching

The JSON and HTML output of the docs endpoint is memoized at boot and
rebuilt on every Rails reload (via `config.to_prepare`). Requests to
the docs endpoint do not regenerate the service definition; they
return the cached strings directly. Memory cost is two strings
(~50-500KB combined). Invalidation happens automatically when contract
files change in development; no manual intervention needed.

### Securing the docs endpoint

The docs endpoint exposes your API's full contract — paths, parameter shapes,
body schemas, error catalog. In production this is information attackers can
use to enumerate endpoints. **By default we recommend disabling the mount in
production**:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  unless Rails.env.production?
    mount Trane::Engine, at: "/sunga-demo/docs"
  end
end
```

If you need docs in production (e.g., for an internal admin team), wrap the
mount in authentication or a custom constraint.

#### With Devise

```ruby
authenticate :user, ->(u) { u.admin? } do
  mount Trane::Engine, at: "/sunga-demo/docs"
end
```

#### With a custom Rack constraint

```ruby
admin_only = lambda { |req| req.env["warden"].user&.admin? }

constraints(admin_only) do
  mount Trane::Engine, at: "/sunga-demo/docs"
end
```

#### Trade-offs

- **Omitting the mount in production** is the strongest guarantee: the path
  simply does not exist, so misconfigured auth or accidental session leaks
  can't expose docs.
- **Wrapping in `constraints` / `authenticate`** lets docs live in production
  but adds the auth layer's failure modes (token leaks, session hijacks).

Choose based on whether your internal team needs docs in prod. This demo's
host `config/routes.rb` mounts the docs endpoint unconditionally in every
environment, including production, with no auth wrapper — a deliberate choice
for a demo app. The env-gate pattern above is available if your own host wants
to restrict docs in production.

### Endpoints

| Path | Content Type | Description |
|---|---|---|
| `<mount_path>` | `text/html` | HTML documentation |
| `<mount_path>.json` | `application/json` | Service Definition JSON |

### Service Definition JSON

The JSON includes everything a client needs to understand the API:

```json
{
  "service": {
    "name": "api"
  },
  "operations": [
    {
      "id": "get_user",
      "summary": "Get a user by id",
      "method": "GET",
      "path": "/users/:id",
      "request": {
        "params": [
          { "name": "id", "type": "integer", "location": "path", "required": true }
        ]
      },
      "responses": [
        {
          "status": 200,
          "fields": [
            { "name": "user", "type": "user" }
          ]
        }
      ],
      "errors": ["UserNotFound"]
    }
  ],
  "representations": [
    {
      "name": "user",
      "fields": [
        { "name": "id", "type": "integer" },
        { "name": "name", "type": "string" },
        { "name": "email", "type": "string" },
        { "name": "birthday", "type": "date", "format": "iso8601" },
        { "name": "nickname", "type": "string", "extra": true }
      ]
    }
  ],
  "errors": [
    { "key": "UserNotFound", "status_code": 404, "description": "User not found" }
  ]
}
```

### Field structure in JSON

Each field includes only the relevant attributes:

```json
{ "name": "id", "type": "integer" }
{ "name": "birthday", "type": "date", "format": "iso8601" }
{ "name": "nickname", "type": "string", "extra": true }
{ "name": "users", "type": "array", "array_of": "user" }
{ "name": "address", "type": "object", "children": [ ... ] }
```

### HTML documentation

The HTML page is a self-contained, polished document with:

- **Sidebar navigation** with color-coded HTTP method badges (GET=blue, POST=green, PATCH=orange, DELETE=red).
- **Operation cards** with collapsible Request, Response, and Errors sections.
- **Representation catalog** with field tables showing types, formats, and extra badges.
- **Error catalog** with status codes and descriptions.
- **Cross-links**: field types that reference representations are clickable links.
- **Responsive layout**: sidebar collapses on mobile screens.
- No external CSS or JavaScript dependencies.

---

## File Structure Conventions

Trane auto-loads contract files from these locations:

```
your-rails-app/
├── app/
│   ├── api_contract/
│   │   ├── errors.rb              # Error catalog
│   │   ├── operations/            # Operation definitions
│   │   │   ├── users.rb
│   │   │   ├── cars.rb
│   │   │   └── admin/             # Subdirectories allowed
│   │   │       └── reports.rb
│   │   └── representations/       # Representation definitions
│   │       ├── user.rb
│   │       └── car.rb
│   ├── controllers/
│   │   └── application_controller.rb   # include Trane::Controller
│   └── errors/                    # Exception classes (standard Ruby)
│       ├── user_not_found.rb
│       └── user_invalid.rb
└── config/
    └── initializers/
        └── trane.rb               # Configuration
```

> **Autoloading note**: Trane registers all configured `contracts_paths` as
> Zeitwerk-ignored paths. The files inside are DSL declarations
> (`Trane.operation`, `Trane.errors`, `Trane.representation`) — they don't
> define constants and would otherwise crash Zeitwerk's eager-load in
> production. Trane loads them explicitly via `config.to_prepare` in the
> Engine. See [Custom Contract Paths](#custom-contract-paths) for overriding
> the default `app/api_contract/` location.

### Loading order

For each configured contracts path (default: `app/api_contract/`):

1. All `errors.rb` files from every path are loaded first (in path declaration order).
2. All other `.rb` files from every path are loaded alphabetically within each path.
3. Boot-time validation runs after all files are loaded.
4. In development, this cycle repeats on every code reload.

---

## Field Types Reference

### Primitive types

| Type | Description | Example value |
|---|---|---|
| `:string` | String | `"Alice"` |
| `:integer` | Integer | `42` |
| `:float` | Float | `3.14` |
| `:boolean` | Boolean | `true` / `false` |
| `:date` | Date | `Date.new(1990, 5, 15)` |
| `:datetime` | DateTime / Time | `Time.now` |
| `:object` | Generic object / passthrough | With block: inline structure. Without block: value passed through as-is. |
| `:array` | Array | (requires `of:`) |

### Representation references

Any symbol that is not a primitive type is treated as a reference to a representation:

```ruby
field :user,    type: :user      # references Trane.representation :user
field :address, type: :address   # references Trane.representation :address
```

### Field options

| Option | Type | Default | Description |
|---|---|---|---|
| `extra:` | Boolean | `false` | When `true`, field is excluded unless requested via `extra_attributes[]`. |
| `format:` | Symbol | `nil` | Format transformation. `:iso8601` calls `.iso8601` on the value. |
| `of:` | Symbol | `nil` | Element type for arrays. Sets the field type to `:array` automatically. |
| `required:` | Boolean | `false` | **Body fields only.** Whether the field must be present in the request body. Documentation only — no runtime validation. |
| `enum:` | Array | `nil` | Set of allowed values. Only valid for scalar primitive types (`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`). Values must match the field's `type:` strictly (no coercion). |

### Field declaration variants

Every `field` must declare its type via `type:`, except in two cases:

1. With `of:` — the type is inferred as `:array`
2. With a block — the type is inferred as `:object`

Combining `type:` with `of:` is allowed and equivalent to the shortcut.

```ruby
# Simple primitive — type: is required
field :name, type: :string

# With format
field :birthday, type: :date, format: :iso8601

# Optional extra field
field :nickname, type: :string, extra: true

# Array of primitives — explicit type:
field :tags, type: :array, of: :string

# Array of representations — explicit type:
field :users, type: :array, of: :user

# Array shorthand — type: inferred as :array from of:
field :items, of: :item

# Representation reference
field :user, type: :user

# Inline nested object — type: inferred as :object from block
field :metadata do
  field :page,     type: :integer
  field :per_page, type: :integer
  field :total,    type: :integer
end

# Deeply nested inline
field :result do
  field :data do
    field :items, type: :array, of: :item
  end
  field :pagination do
    field :next_page, type: :string
  end
end

# Object passthrough (variable structure — no block)
field :payload, type: :object
```

### Enum values

Fields and query params with a finite set of allowed values can declare them via `enum:`:

```ruby
# In a representation or response
field :status, type: :string, enum: ['active', 'archived', 'deleted']

# In a body
body do
  field :artist do
    field :genre, type: :string, enum: ['rock', 'pop', 'jazz']
  end
end

# In a query param
query :sort, type: :string, enum: ['asc', 'desc']
```

`enum:` is supported for these types: `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`. Using it on `:array`, `:object`, or representation references raises `ArgumentError`.

Values are validated for strict type coherence at definition time:

- `type: :integer, enum: [1.0]` → raises (Float not accepted for Integer).
- `type: :float, enum: [1]` → raises (Integer not accepted for Float).
- `type: :date, enum: [DateTime.now]` → raises (DateTime not accepted for Date).
- `type: :datetime, enum: [Date.today]` → raises (Date not accepted for DateTime).

For `:datetime`, accepted classes are `DateTime`, `Time`, and `ActiveSupport::TimeWithZone` (when loaded).

`enum:` is **not accepted in `path` params** — passing it raises `ArgumentError`.

**Documentation only**: Trane does not validate at runtime that received values match the enum. The declaration appears in the Service Definition JSON and HTML docs.

---

## Complete Example

### Error catalog

```ruby
# app/api_contract/errors.rb
Trane.errors do
  error :UserNotFound, status_code: 404, description: "User not found"
  error :UserInvalid,  status_code: 422, description: "User is invalid"
  error :CarNotFound,  status_code: 404, description: "Car not found"
  error :CarInvalid,   status_code: 422, description: "Car is invalid"
end
```

### Representations

```ruby
# app/api_contract/representations/user.rb
Trane.representation :user do
  field :id,         type: :integer
  field :name,       type: :string
  field :last_name,  type: :string
  field :email,      type: :string
  field :birthday,   type: :date, format: :iso8601
  field :created_at, type: :datetime, format: :iso8601
end

# app/api_contract/representations/car.rb
Trane.representation :car do
  field :id,         type: :integer
  field :brand,      type: :string
  field :model,      type: :string
  field :year,       type: :integer
  field :color,      type: :string
  field :created_at, type: :datetime, format: :iso8601
end
```

### Operations

```ruby
# app/api_contract/operations/users.rb
Trane.operation :list_users do
  summary "List all users"

  response 200 do
    field :users, type: :array, of: :user
  end
end

Trane.operation :get_user do
  summary "Get a user by id"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
  end
end

Trane.operation :create_user do
  summary "Create a user"

  request do
    body do
      field :user do
        field :name,      type: :string
        field :last_name, type: :string
        field :email,     type: :string
        field :birthday,  type: :date
      end
    end
  end

  response 201 do
    field :user, type: :user
  end

  errors do
    key :UserInvalid
  end
end

Trane.operation :update_user do
  summary "Update a user"

  request do
    path :id, type: :integer
    body do
      field :user do
        field :name,      type: :string
        field :last_name, type: :string
        field :email,     type: :string
        field :birthday,  type: :date
      end
    end
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
    key :UserInvalid
  end
end

Trane.operation :destroy_user do
  summary "Delete a user"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :message, type: :string
  end

  errors do
    key :UserNotFound
  end
end
```

### Exception classes

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

### Controller

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :set_user, only: %i[show update destroy]

  def index
    @users = User.all
    render contract: { users: @users }
  end

  def show
    render contract: { user: @user }
  end

  def create
    @user = User.new(user_params)
    @user.save || raise(UserInvalid.new(@user.errors))
    render contract: { user: @user }, status: :created
  end

  def update
    @user.update(user_params) || raise(UserInvalid.new(@user.errors))
    render contract: { user: @user }
  end

  def destroy
    @user.destroy!
    render contract: { message: "User deleted successfully" }
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    raise UserNotFound
  end

  def user_params
    params.expect(user: [:name, :last_name, :email, :birthday])
  end
end
```

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get    "/users",     to: "users#index",   contract: { operation: :list_users }
  post   "/users",     to: "users#create",  contract: { operation: :create_user }
  get    "/users/:id", to: "users#show",    contract: { operation: :get_user }
  match  "/users/:id", via: [:patch, :put], to: "users#update",  contract: { operation: :update_user }
  delete "/users/:id", to: "users#destroy", contract: { operation: :destroy_user }
end
```

### Example responses

**GET /users**

```json
{
  "users": [
    {
      "id": 1,
      "name": "Alice",
      "last_name": "Smith",
      "email": "alice@example.com",
      "birthday": "1990-05-15",
      "created_at": "2026-04-01T12:00:00+00:00"
    }
  ]
}
```

**GET /users/999**

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

**POST /users** (validation error)

```json
{
  "errors": [
    {
      "key": "UserInvalid",
      "message": "Name can't be blank, Email can't be blank"
    }
  ]
}
```

---

## Testing

### Running the gem's test suite

```bash
cd trane
bundle install
bundle exec rspec
```

### Linting

```bash
bundle exec rubocop
```

`bundle exec rake` (no args) runs both `rspec` and `rubocop` — the same two checks CI runs.

### Test structure

```
trane/spec/
├── spec_helper.rb
├── trane/                            # Unit tests
│   ├── configuration_spec.rb
│   ├── types_spec.rb
│   ├── registry_spec.rb
│   ├── field_node_spec.rb
│   ├── field_builder_spec.rb
│   ├── param_definition_spec.rb
│   ├── operation_definition_spec.rb
│   ├── representation_definition_spec.rb
│   ├── error_registry_spec.rb
│   ├── serializer_spec.rb
│   ├── extra_attributes_filter_spec.rb
│   ├── contract_validator_spec.rb
│   ├── boot_validator_spec.rb
│   └── docs/
│       ├── service_definition_spec.rb
│       └── html_renderer_spec.rb
└── integration/                      # Integration tests (dummy Rails app)
    ├── integration_helper.rb
    ├── full_lifecycle_spec.rb
    ├── error_handling_spec.rb
    ├── extra_attributes_spec.rb
    ├── docs_endpoint_spec.rb
    └── dummy/                        # Minimal Rails app for testing
```

### Running specific test groups

```bash
bundle exec rspec spec/trane/           # Unit tests only
bundle exec rspec spec/integration/     # Integration tests only
bundle exec rspec spec/trane/docs/      # Docs tests only
```

---

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
