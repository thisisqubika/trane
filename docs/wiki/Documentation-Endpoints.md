# Documentation Endpoints

Trane ships a Rails Engine that serves the auto-generated documentation
(HTML + JSON). Mount it explicitly in your host's `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  # ... your API routes ...

  mount Trane::Engine, at: "/my-api/docs"
end
```

After mounting:

- `GET /my-api/docs` → interactive HTML documentation
- `GET /my-api/docs.json` → machine-readable Service Definition JSON

The mount path is host-controlled. You can wrap it in `constraints:` (e.g. for
authentication) or omit it entirely in environments where you don't want docs
exposed (e.g. production).

The published `service.name` is derived from `Rails.application.name`
(`MyApi::Application` → `"my-api"`). Route prefixes are the host's decision:
scope your routes and mount the docs engine wherever you want —
interpolating `Rails.application.name` keeps both in sync with the
descriptor.

## Caching

The JSON and HTML output of the docs endpoint is memoized at boot and rebuilt
on every Rails reload (via `config.to_prepare`). Requests to the docs endpoint
do not regenerate the service definition; they return the cached strings
directly. Memory cost is two strings (~50-500KB combined). Invalidation
happens automatically when contract files change in development; no manual
intervention needed.

## Securing the docs endpoint

The docs endpoint exposes your API's full contract — paths, parameter shapes,
body schemas, error catalog. In production this is information attackers can
use to enumerate endpoints. **By default we recommend disabling the mount in
production**:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  unless Rails.env.production?
    mount Trane::Engine, at: "/my-api/docs"
  end
end
```

If you need docs in production (e.g., for an internal admin team), wrap the
mount in authentication or a custom constraint.

### With Devise

```ruby
authenticate :user, ->(u) { u.admin? } do
  mount Trane::Engine, at: "/my-api/docs"
end
```

### With a custom Rack constraint

```ruby
admin_only = lambda { |req| req.env["warden"].user&.admin? }

constraints(admin_only) do
  mount Trane::Engine, at: "/my-api/docs"
end
```

### Trade-offs

- **Omitting the mount in production** is the strongest guarantee: the path
  simply does not exist, so misconfigured auth or accidental session leaks
  can't expose docs.
- **Wrapping in `constraints` / `authenticate`** lets docs live in production
  but adds the auth layer's failure modes (token leaks, session hijacks).

Choose based on whether your internal team needs docs in prod.

## Endpoints

| Path | Content Type | Description |
|---|---|---|
| `<mount_path>` | `text/html` | HTML documentation |
| `<mount_path>.json` | `application/json` | Service Definition JSON |

## Service Definition JSON

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

## Field structure in JSON

Each field includes only the relevant attributes:

```json
{ "name": "id", "type": "integer" }
{ "name": "birthday", "type": "date", "format": "iso8601" }
{ "name": "nickname", "type": "string", "extra": true }
{ "name": "users", "type": "array", "array_of": "user" }
{ "name": "address", "type": "object", "children": [ ... ] }
```

## HTML documentation

The HTML page is a self-contained, polished document with:

- **Sidebar navigation** with color-coded HTTP method badges (GET=blue, POST=green, PATCH=orange, DELETE=red).
- **Operation cards** with collapsible Request, Response, and Errors sections.
- **Representation catalog** with field tables showing types, formats, and extra badges.
- **Error catalog** with status codes and descriptions.
- **Cross-links**: field types that reference representations are clickable links.
- **Responsive layout**: sidebar collapses on mobile screens.
- No external CSS or JavaScript dependencies.
