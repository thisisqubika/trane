# Representations

Representations define the shape of serializable objects. They are declarative
schemas — no Ruby logic, just field definitions.

## File location

```
app/api_contract/representations/*.rb
```

## Basic representation

```ruby
Trane.representation :user do
  field :id,         type: :integer
  field :name,       type: :string
  field :email,      type: :string
  field :created_at, type: :datetime, format: :iso8601
end
```

## Fields with format

The `format:` option controls how values are serialized. Currently supported:

```ruby
field :birthday,   type: :date,     format: :iso8601   # calls .iso8601 → "1990-05-15"
field :created_at, type: :datetime, format: :iso8601   # calls .iso8601 → "2026-04-15T12:00:00+00:00"
```

When `format: :iso8601` is set, Trane calls `.iso8601` on the value. If the
value does not respond to `.iso8601`, it is passed through unchanged.

## Extra fields (optional)

Fields marked `extra: true` are excluded from responses by default. Clients
must explicitly request them via the `extra_attributes[]` query parameter —
see [Extra Attributes](Extra-Attributes.md), including the security note on
what `extra:` does and does not protect.

```ruby
Trane.representation :user do
  field :id,       type: :integer
  field :name,     type: :string
  field :nickname, type: :string, extra: true    # excluded unless requested
  field :bio,      type: :string, extra: true    # excluded unless requested
end
```

## Array fields

```ruby
Trane.representation :user do
  field :id,      type: :integer
  field :hobbies, type: :array, of: :string     # array of primitives
  field :pets,    type: :array, of: :pet        # array of representations
end
```

## Representation references

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

This creates nested serialization: the `:address` field will be serialized
according to the `:address` representation.

Representations can be defined in any order — references are resolved at
serialization time, not at definition time.

## Object passthrough (variable structure)

For fields whose structure is not known at definition time, use `:object`
without a block:

```ruby
Trane.representation :event do
  field :type,    type: :string
  field :payload, type: :object     # passed through as-is, no serialization
end
```

`:object` has two distinct uses:

- **With a block** — declares an inline nested structure; only the declared child fields are serialized.
- **Without a block** — acts as a passthrough; the value is included in the response exactly as provided, with no transformation or recursive validation.

See the [Field Types Reference](Field-Types-Reference.md) for every type,
option, and declaration variant.
