# Trane Wiki

Trane is a contract enforcement and documentation layer for Rails APIs: it
enforces structured JSON responses, provides deterministic serialization via
contract-based representations, captures errors globally, and publishes API
documentation (HTML + JSON).

New to Trane? Start with the [Quick Start in the README](../../README.md).

## Guides

| Page | What it covers |
|---|---|
| [Configuration](Configuration.md) | Options, contract file locations and loading order, lifecycle/freezing, testing helper |
| [Representations](Representations.md) | Declaring serializable shapes: fields, formats, arrays, references, passthrough |
| [Operations](Operations.md) | Endpoint contracts: request DSL (path/query/body), response DSL, error keys |
| [Error Handling](Error-Handling.md) | Error catalog, exception matching, response envelope, unhandled errors |
| [Controller Integration](Controller-Integration.md) | The mixins, `render contract:`, status mapping, raising errors |
| [Routes](Routes.md) | The `contract:` route keyword and how it wires routes to operations |
| [Serialization](Serialization.md) | How values are extracted and serialized, nil handling, nesting |
| [Extra Attributes](Extra-Attributes.md) | Optional fields clients opt into via `extra_attributes[]` |
| [Validation](Validation.md) | Strict response validation, boot-time contract validation, route cross-checks, `trane:check` |
| [Documentation Endpoints](Documentation-Endpoints.md) | Mounting the docs engine, securing it, the Service Definition JSON |
| [Field Types Reference](Field-Types-Reference.md) | Every type, field option, declaration variant, and `enum:` |
| [Architecture](Architecture.md) | Process-level state, registry concurrency model, legacy API |
| [Complete Example](Complete-Example.md) | A full worked CRUD example, end to end |

## Naming

**Trane** is named after John Coltrane. The name also reads as **train**, a
fitting companion for a gem that runs entirely on **Rails**. Trane draws its
inspiration from **Angus**, a predecessor gem named after Angus Young.
