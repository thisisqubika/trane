# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-14

First public release.

### Added

- Contract DSL: `Trane.operation`, `Trane.representation`, and `Trane.errors`
  for declaring API contracts as code, auto-loaded from `app/api_contract/`
  (configurable via `config.trane.contracts_paths`).
- `render contract:` controller integration with deterministic serialization:
  responses contain exactly the declared fields (extra `extra: true` fields
  are client-opt-in via `extra_attributes[]`).
- Structured error handling: raised exceptions map to a registered error
  catalog and render a consistent JSON error envelope; unhandled exceptions
  are reported through `Rails.error` and logged before rendering a generic
  500 (verbose details only in local environments).
- Strict contract validation (`:raise` / `:log` / `:ignore`, auto-detected by
  environment): missing keys, undeclared keys, and composite values in scalar
  leaf fields.
- Boot-time validation of contract referential integrity, route `contract:`
  metadata validation with "did you mean" hints, and a `trane:check` rake
  task.
- Auto-generated documentation (HTML + Service Definition JSON) served by a
  mountable engine, cached per boot/reload.
- Fail-closed defaults: `render contract:` on a route without contract
  metadata raises by default (`on_missing_operation` opt-out), and
  configuration setters reject unknown modes.

[0.1.0]: https://github.com/thisisqubika/trane/releases/tag/v0.1.0
