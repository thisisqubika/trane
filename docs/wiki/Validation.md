# Validation

Trane validates at three moments: **at request time** (strict contract
validation of serialized responses), **at boot** (referential integrity of
contract definitions), and **at route-draw time** (shape of the `contract:`
route metadata).

## Strict contract validation (request time)

Strict validation checks that serialized responses match the declared
contract. It runs after serialization and before the response is sent.

### What it checks

1. **Missing fields**: All non-extra declared fields must be present in the serialized result.
2. **Undeclared fields**: No keys in the result that aren't declared in the response definition.
3. **Composite values in scalar leaf fields**: no Hash or Array where a scalar
   (`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`) was
   declared.
4. **Nested validation**: Recursively validates fields that reference representations.

The composite-value check catches the accidental over-exposure case where a
whole object (e.g. a model's full `as_json`) is passed for a field that was
meant to carry one value; the serializer emits leaf values verbatim, so
without this check the entire object would reach the client. Scalar leaf
values of the *wrong scalar type* (e.g. a String in an `:integer` field) are
not flagged — types are documentation, only composites are rejected.

### Modes

| Mode | Behavior |
|---|---|
| `:raise` | Raises `Trane::ContractViolation` with all violations listed. |
| `:log` | Logs all violations via `Rails.logger.warn`. Response is still sent. |
| `:ignore` | Skips validation entirely. |

**Operational note on `:log`:** violations are logged once per response, with
no deduplication or rate-limiting — a broken contract on a high-traffic
endpoint logs a multi-line warning for every request until it is fixed. If
that volume is a concern, rely on your log pipeline's rate-limiting/alerting
rather than silencing Trane (`:ignore` also disables detection).

### Configuration and auto-detection

```ruby
Trane.configure do |config|
  config.strict_mode = :raise   # explicit mode
  config.strict_mode = nil      # auto-detect (default)
end
```

| Environment | Auto-detected mode |
|---|---|
| `development` | `:raise` |
| `test` | `:raise` |
| `production` (and any other) | `:log` |

### Error messages

When a violation occurs in `:raise` mode:

```
Trane::ContractViolation: Trane contract violations:
  count: missing from response
  user.email: missing from response
  extra_field: undeclared field in response
  user.name: composite Hash value in scalar field (declared type :string)
```

### Object type (passthrough)

Fields with `:object` type and no block are never recursively validated. Their
values are accepted as-is (including Hashes — declare `:object` when a field
intentionally carries free-form data).

## Boot-time validation

Trane validates the referential integrity of all contract definitions when
the Rails app boots (and on every code reload in development).

### What it checks

1. **Representation references**: Every field in an operation's response that references a representation (e.g., `field :user, :user`) must have a corresponding `Trane.representation :user` defined.
2. **Array element types**: Every `field :items, :array, of: :item` must have the `:item` representation defined (if it's not a primitive type).
3. **Error key references**: Every `key :ErrorName` in an operation's `errors` block must have a corresponding entry in `Trane.errors`.

Fields with primitive types (`:string`, `:integer`, `:date`, `:object`, etc.)
are not checked against the representation registry.

### When it runs

Validation is gated on `config.eager_load`. It only runs when the host
application has `config.eager_load = true`.

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

## Route contract validation

The `contract: { operation: :name }` metadata on routes is validated so typos
fail loud instead of silently bypassing the contract or surfacing only when a
request hits the route. Both checks raise `Trane::RoutingContractError` (a
subclass of `Trane::Error`).

**A. `contract:` hash shape** — runs whenever a route is drawn (boot, and
`bin/rails routes` in development). The only accepted key is `:operation`; it
must be present and non-blank.

```ruby
get "/users/:id", to: "users#show", contract: { operaton: :get_user }
# Trane::RoutingContractError: Unknown key `operaton` in contract:. Did you mean `operation`?

get "/users/:id", to: "users#show", contract: {}
# Trane::RoutingContractError: contract: requires a non-empty :operation
```

**B. Route → registry cross-check** — every route whose `contract:` names an
operation must reference one that is actually registered. Gated on
`config.eager_load` like the contract checks above (runs at boot in
production/CI, skipped in development), and always run by `bin/rails
trane:check`:

```
Trane::RoutingContractError: Trane route/registry cross-check failed:
  GET /api/artists/:id(.:format) references operation :get_artistt, but no such operation is registered (did you mean :get_artist?)
```

**Known limitation** — a typo in the `contract` *key itself* (e.g.
`contractt: { operation: :get_user }`) cannot be detected: Trane's routing
extension never sees the misspelled key, so the route is indistinguishable
from one that legitimately declares no contract (like `/up`). Such a route
silently loses its contract — but `render contract:` on it fails loud by
default (see
[Controllers without contracts](Controller-Integration.md#controllers-without-contracts)).
Spell the key `contract` carefully.
