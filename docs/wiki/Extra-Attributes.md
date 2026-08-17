# Extra Attributes (Optional Fields)

Fields marked with `extra: true` are excluded from responses by default.
Clients request them via the `extra_attributes[]` query parameter using
dot-notation paths.

## Defining extra fields

```ruby
Trane.representation :user do
  field :id,       type: :integer
  field :name,     type: :string
  field :nickname, type: :string, extra: true
  field :bio,      type: :string, extra: true
end
```

## Requesting extra fields

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

## Path construction

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

## Nested extra fields

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

## Default response (no extra_attributes)

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

## Response with extra_attributes

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

## Limits

The `extra_attributes[]` parameter accepts at most 100 values per request;
values beyond the cap are ignored. Non-array/non-string inputs are treated as
an empty request.
