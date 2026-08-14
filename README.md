# Trane

[![CI](https://github.com/thisisqubika/trane/actions/workflows/ci.yml/badge.svg)](https://github.com/thisisqubika/trane/actions/workflows/ci.yml)

Contract enforcement and documentation layer for Rails APIs.

Declare your API's contract — operations, representations, errors — as code,
and Trane takes it from there:

- **Deterministic serialization**: responses contain exactly the fields the
  contract declares, nothing more. No accidental `password_digest` in a JSON.
- **Contract validation**: drift between what you declared and what you serve
  fails loud in development and gets logged in production.
- **Structured error handling**: raise your domain exceptions; clients get a
  consistent JSON error envelope with the right status code.
- **Auto-generated documentation**: polished HTML + machine-readable JSON,
  always in sync with the contract, served from a mountable engine.

## Installation

Add Trane to your Gemfile:

```ruby
gem "trane"
```

Then run:

```bash
bundle install
```

## Supported versions

| Component | Versions |
|---|---|
| Ruby | >= 3.2 |
| Rails | 7.2, 8.0, 8.1 |

## Quick Start

**1. Define your error catalog** — `app/api_contract/errors.rb`:

```ruby
Trane.errors do
  error :UserNotFound, status_code: 404, description: "User not found"
end
```

**2. Define a representation** — `app/api_contract/representations/user.rb`:

```ruby
Trane.representation :user do
  field :id,    type: :integer
  field :name,  type: :string
  field :email, type: :string
end
```

**3. Define an operation** — `app/api_contract/operations/users.rb`:

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

**4. Include the controller concern** (in your API base controller):

```ruby
class ApplicationController < ActionController::API
  include Trane::Controller
end
```

**5. Render through the contract**:

```ruby
class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    render contract: { user: @user }
  rescue ActiveRecord::RecordNotFound
    raise UserNotFound
  end
end
```

**6. Wire the route to the operation** — `config/routes.rb`:

```ruby
get "/users/:id", to: "users#show", contract: { operation: :get_user }
```

That's it. `GET /users/1` now serves exactly the declared fields, and a
missing user renders `{"errors":[{"key":"UserNotFound","message":"User not
found"}]}` with a 404.

**Optional — mount the documentation endpoints**:

```ruby
# config/routes.rb
unless Rails.env.production?
  mount Trane::Engine, at: "/my-api/docs"
end
```

`GET /my-api/docs` serves the HTML documentation and `/my-api/docs.json` the
machine-readable service definition. The docs expose your full API surface —
see [securing the docs endpoint](docs/wiki/Documentation-Endpoints.md#securing-the-docs-endpoint)
before mounting in production.

## Documentation

The full guides live in the wiki:

| Guide | What it covers |
|---|---|
| [Configuration](docs/wiki/Configuration.md) | Options, contract file locations and loading order, lifecycle, testing helper |
| [Representations](docs/wiki/Representations.md) | Fields, formats, arrays, references, passthrough |
| [Operations](docs/wiki/Operations.md) | Request DSL (path/query/body), response DSL, error keys |
| [Error Handling](docs/wiki/Error-Handling.md) | Error catalog, exception matching, response envelope, unhandled errors |
| [Controller Integration](docs/wiki/Controller-Integration.md) | The mixins, `render contract:`, status mapping, raising errors |
| [Routes](docs/wiki/Routes.md) | The `contract:` route keyword |
| [Serialization](docs/wiki/Serialization.md) | Value extraction, nil handling, nesting |
| [Extra Attributes](docs/wiki/Extra-Attributes.md) | Optional fields clients opt into per request |
| [Validation](docs/wiki/Validation.md) | Strict response validation, boot-time checks, `trane:check` |
| [Documentation Endpoints](docs/wiki/Documentation-Endpoints.md) | Mounting, securing, the Service Definition JSON |
| [Field Types Reference](docs/wiki/Field-Types-Reference.md) | Every type, option, and declaration variant |
| [Architecture](docs/wiki/Architecture.md) | Process-level state, concurrency model, legacy API |
| [Complete Example](docs/wiki/Complete-Example.md) | A full CRUD example, end to end |

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
