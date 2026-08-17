# Operations

Operations define the contract for an API endpoint: what it receives (request)
and what it returns (response).

## File location

```
app/api_contract/operations/**/*.rb
```

Files can be nested in subdirectories for organization.

## Minimal operation

```ruby
Trane.operation :list_users do
  summary "List all users"

  response 200 do
    field :users, type: :array, of: :user
  end
end
```

## Operation with request parameters

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

## Request DSL

The `request` block supports three kinds of parameters:

### Path parameters

```ruby
request do
  path :id, type: :integer
  path :user_id, type: :integer
end
```

Path params are always required by definition (they're part of the URL). The
`required:` option is not accepted — pass it and Trane raises an
`ArgumentError`.

### Query parameters

```ruby
request do
  query :page,     type: :integer, required: false
  query :per_page, type: :integer, required: false
  query :status,   type: :string,  required: false
end
```

`required:` defaults to `false` for query params.

### Body schema

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

`required:` is **not accepted** in response fields or representations —
passing it raises `ArgumentError`. For input contracts, see also `path`
(always required, kwarg not accepted) and `query` (default `required: false`).

**Documentation only**: Trane does not yet validate that required body fields
are present in incoming requests — this declaration affects the published
JSON/HTML docs.

The body supports all field types including nested objects, arrays, and
representation references:

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

## Response DSL

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
  field :data,    type: :object                   # passthrough (no block = variable structure)
  field :result do                                # inline nested object
    field :score, type: :integer
    field :label, type: :string
  end
end
```

## Error keys

Operations declare which errors they may produce:

```ruby
errors do
  key :UserNotFound
  key :UserInvalid
end
```

Each key must correspond to an error defined in the error catalog (see
[Error Handling](Error-Handling.md)). This is validated at boot time.
