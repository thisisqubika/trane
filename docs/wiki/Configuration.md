# Configuration

Configure Trane in an initializer:

```ruby
# config/initializers/trane.rb
Trane.configure do |config|
  config.strict_mode          = nil     # nil (auto-detect), :raise, :log, or :ignore
  config.on_missing_operation = :raise  # :raise, :log, or :fallback
end
```

## Options

| Option | Default | Description |
|---|---|---|
| `strict_mode` | `nil` | Controls response contract validation behavior — see [Validation](Validation.md). |
| `on_missing_operation` | `:raise` | What `render contract:` does when the route declared no `contract:` — see [Controller Integration](Controller-Integration.md#controllers-without-contracts). |

Both setters validate their value at assignment time: an unknown mode raises
`Trane::Error` with the accepted values, instead of silently disabling the
feature.

## Strict mode

When `strict_mode` is `nil`, it auto-detects based on Rails environment:

| Environment | Behavior |
|---|---|
| `development` | `:raise` — raises `Trane::ContractViolation` |
| `test` | `:raise` — raises `Trane::ContractViolation` |
| `production` (and any other) | `:log` — logs a warning via `Rails.logger.warn` |

You can override this explicitly:

```ruby
config.strict_mode = :raise   # Always raise on contract violations
config.strict_mode = :log     # Always log warnings
config.strict_mode = :ignore  # Skip validation entirely
```

See [Validation](Validation.md) for what each mode checks.

## File structure conventions

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
> Engine.

## Custom contract paths

By default, Trane loads contract files from `app/api_contract/` relative to
the Rails application root. To use a different location — or multiple
locations — set `contracts_paths` in `config/application.rb`:

```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    config.trane.contracts_paths = ["app/contracts", "engines/billing/app/contracts"]
  end
end
```

**Timing requirement**: this setting must be in `config/application.rb`, NOT
in `config/initializers/trane.rb`. The Engine's `trane.ignore_autoload_paths`
initializer runs before config initializers are loaded; by the time
`config/initializers/trane.rb` is evaluated, the autoload ignore step has
already passed and Zeitwerk will attempt to eager-load the contract files.

**Validation**: each entry must be a non-blank String or Pathname without glob
characters. An empty array or a non-array value raises `Trane::Error` at boot.

## Loading order

For each configured contracts path (default: `app/api_contract/`):

1. Every `errors.rb` from each base path is loaded first (in path declaration order).
2. All other `.rb` files from each base path are loaded next (sorted alphabetically within each path).
3. Boot-time validation runs after all files are loaded.
4. In development, this cycle repeats on every code reload.

This guarantees that error registrations from any path are available when
operations from any other path reference them.

## Configuration lifecycle and freezing

`Trane::Configuration` is frozen once, at boot, before Rails draws routes — but
that ordering is incidental, not a dependency: route drawing never reads
`Trane::Configuration` at all (`strict_mode` is read only when a response is
rendered). The freeze exists to prevent post-boot mutation in multi-threaded
servers (Puma, Falcon). The expected lifecycle is:

1. `config/initializers/trane.rb` sets the options.
2. The Engine initializer `trane.freeze_configuration` (runs after `:load_config_initializers`, before Rails' Finisher batch) freezes the configuration.
3. Rails' Finisher batch draws routes.

After the freeze, any setter raises `FrozenError`. This guarantees running
requests observe a consistent configuration.

## Testing with a different configuration

Use `Trane::Testing.with_configuration` to temporarily reconfigure, run a
block, then restore:

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

`with_configuration` is opt-in — it is not loaded by default. Add
`require "trane/testing"` to your test helper or individual spec file.

The helper snapshots the complete configuration state (all options and the
frozen flag), resets, applies the given attributes, freezes, yields, and
restores the snapshot — even if the block raises. It does not touch the route
set: `strict_mode` is read when a response is rendered, never when routes are
drawn.

To reset all Trane state between tests (registry, configuration, and docs
cache in one call), use `Trane.reset!` — see [Architecture](Architecture.md).

## Response envelopes

Hosts serving a pre-existing contract can wrap every response in their own
envelope instead of Trane's default shape.

```ruby
# config/initializers/trane.rb
Trane.configure do |config|
  config.success_envelope = ->(body) { { status: "success" }.merge(body) }

  config.error_envelope = lambda do |exception, definition|
    { status: "error",
      messages: [ { key: definition ? definition.key.to_s : exception.class.name,
                    dsc: exception.message } ] }
  end

  config.rescue_rails_reserved = true
end
```

| Option | Signature | Default |
|---|---|---|
| `success_envelope` | `(Hash) -> Hash` — the serialized response, returning what to encode | identity |
| `error_envelope` | `(Exception, ErrorDefinition or nil) -> Hash` — `nil` when no error is registered | the `{"errors":[{"key","message"}]}` shape; message gated to local environments only when no error is registered |
| `rescue_rails_reserved` | `true` / `false` | `false` — reserved exceptions are re-raised for Rails to map |

The status code is **not** the envelope's concern: it stays derived from the
definition (or 500), so body and status cannot drift apart.

**A custom `error_envelope` opts out of the default's verbosity gating.** The
built-in shape only gates the message by environment on the unregistered path
(`definition` is `nil`): an unhandled exception's message is written for logs
and can carry SQL, record values or internal hostnames, so it only reaches
local environments. A *registered* Trane error's message is included in every
environment, because registering the error is how a host curates it. A custom
`error_envelope` that echoes `exception.message` unconditionally is choosing
to expose that for the unregistered case too, and should mean it.

Referencing an autoloaded constant from these callables is fine, but pass a
**lambda that delegates**, not a `Method` object: config initializers run before
Rails sets up the autoloader, so `MyApp::Envelope.method(:error)` raises
`NameError` at boot while `->(e, d) { MyApp::Envelope.error(e, d) }` resolves at
call time.
