# Field Types Reference

## Primitive types

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

## Representation references

Any symbol that is not a primitive type is treated as a reference to a
representation:

```ruby
field :user,    type: :user      # references Trane.representation :user
field :address, type: :address   # references Trane.representation :address
```

## Field options

| Option | Type | Default | Description |
|---|---|---|---|
| `extra:` | Boolean | `false` | When `true`, field is excluded unless requested via `extra_attributes[]`. |
| `format:` | Symbol | `nil` | Format transformation. `:iso8601` calls `.iso8601` on the value. |
| `of:` | Symbol | `nil` | Element type for arrays. Sets the field type to `:array` automatically. |
| `required:` | Boolean | `false` | **Body fields only.** Whether the field must be present in the request body. Documentation only — no runtime validation. |
| `enum:` | Array | `nil` | Set of allowed values. Only valid for scalar primitive types (`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`). Values must match the field's `type:` strictly (no coercion). |

## Field declaration variants

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

## Enum values

Fields and query params with a finite set of allowed values can declare them
via `enum:`:

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

`enum:` is supported for these types: `:string`, `:integer`, `:float`,
`:boolean`, `:date`, `:datetime`. Using it on `:array`, `:object`, or
representation references raises `ArgumentError`.

Values are validated for strict type coherence at definition time:

- `type: :integer, enum: [1.0]` → raises (Float not accepted for Integer).
- `type: :float, enum: [1]` → raises (Integer not accepted for Float).
- `type: :date, enum: [DateTime.now]` → raises (DateTime not accepted for Date).
- `type: :datetime, enum: [Date.today]` → raises (Date not accepted for DateTime).

For `:datetime`, accepted classes are `DateTime`, `Time`, and
`ActiveSupport::TimeWithZone` (when loaded).

`enum:` is **not accepted in `path` params** — passing it raises
`ArgumentError`.

**Documentation only**: Trane does not validate at runtime that received
values match the enum. The declaration appears in the Service Definition JSON
and HTML docs.
