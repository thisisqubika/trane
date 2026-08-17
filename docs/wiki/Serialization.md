# Serialization

## How objects are serialized

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

The output is built by iterating the **declared** fields, not the data's keys
— undeclared data can never leak into the response structure.

## Value extraction

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

For Hash data, Trane tries the symbol key first, then the string key. For
objects, it calls `public_send(field_name)`. If the method doesn't exist,
`nil` is returned.

## Nil handling

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

## Nested serialization example

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
