# Architecture

Host-relevant guarantees about how Trane holds and updates its state.

## Process-level state

Trane keeps a single registry (operations, representations, errors) and a
single configuration per Ruby process, following the standard Rails model of
one application per process. Running multiple `Rails::Application` instances
in one process is not supported.

The public DSL (`Trane.operation`, `Trane.representation`, `Trane.errors`,
`Trane.configure`) and the lookup helpers (`Trane.registry`,
`Trane.configuration`) all address that process-level state. Registrations
made before Rails boots (e.g. in unit specs that never load Rails) land in
the same registry the booted application uses.

## Registry concurrency model

`Trane::Registry` exposes a single frozen snapshot via `Registry.operations`,
`.representations`, and `.errors`. Reads are lock-free.

Reload paths (`config.to_prepare` in the Engine, integration test setup) use
`Registry.replace! do |builder| ... end` to build a new snapshot atomically;
readers in other threads see either the prior or the new snapshot, never a
partially-rebuilt state. If the block raises, the prior snapshot is preserved
unchanged.

Direct `Registry.register_*` calls outside `replace!` still work (used by unit
specs); each call allocates a new snapshot via copy-on-write.

## Resetting between tests

`Trane.reset!` restores Trane to a pristine state in one call: it empties the
registry (snapshot and derived caches), clears the configuration (values and
frozen flag), and invalidates the docs cache. Intended for test suites that
need isolation between examples.

`Trane.configuration.reset!` (or the shim
`Trane::Configuration.instance.reset!`) is still available to reset only the
configuration. To temporarily reconfigure inside a block instead, see
[Testing with a different configuration](Configuration.md#testing-with-a-different-configuration).

## Backwards compatibility

The legacy module-level API still works:

```ruby
Trane::Registry.operations           # same as Trane.registry.operations
Trane::Configuration.instance.reset! # same as Trane.configuration.reset!
```

Both forms delegate to the process-level state.
