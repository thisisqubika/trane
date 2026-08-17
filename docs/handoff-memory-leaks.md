# Handoff — memory leak audit

**Date:** 2026-08-11
**Branch:** `init_2` (base: `a443db2`)
**Scope:** all of `lib/` (~2,333 LOC). Covers item 8 of `docs/TODO.md`
("check for possible memory leaks"); the second half of that item — adding a
tool that validates it continuously — **was left pending**, see
[Pending](#pending).
**Measurement environment:** Ruby 3.4.6, Rails 8.1.3.1, arm64-darwin24.

---

## Status (2026-08-13) — everything closed

All 4 findings were validated against the code (every measurement reproduced
empirically, Ruby 3.4.7) and resolved:

- **Finding 1 — fixed.** `rails_reserved_classes` was replaced by
  `rails_reserved_names`: it memoizes names (Strings) and compares against
  `klass.ancestors` by name. No pinning and no post-reload development bug.
  A regression spec simulating the reload is included.
- **Finding 2 — closed by design.** Multi-app support was removed
  (`hooks_registry`, `ApplicationHooks`, `with_application`, etc. no longer
  exist); Trane has a single process-level registry and configuration, plus
  `Trane.reset!` for specs.
- **Finding 3 — fixed.** Constant thread-local key
  (`Instance::ACTIVE_BUILDERS_KEY`) holding a `{object_id => builder}` Hash
  with `delete` in the `ensure`. No dynamic symbols and no leftover keys; a
  hygiene spec is included.
- **Finding 4 — mitigated.** The invariant is documented on all three methods
  (current-snapshot-owned objects only) + a defensive bound
  (`Instance::MAX_CACHE_ENTRIES`): past it, results are built without caching.
- **Pending 1 (continuous validation) — resolved.** Measurements A and B are
  now `spec/trane/memory_regression_spec.rb` (a `heap_live_slots` threshold,
  validated to detect a 1-object-per-iteration leak).
- **Out of scope (mutex contention) — gone** along with multi-app:
  `Trane.registry` is an ivar read.

The rest of the document is preserved as the record of the original audit;
file:line references correspond to the `a443db2` base.

---

## Summary

The hot path **has no leaks**. The immutable-snapshot design with cache
invalidation on every `replace!` holds up: 200k requests left +40 live slots
and 5k reload cycles left +44 slots, both after a full GC.

**4 real leaks were found, none on the production request path.** Ordered by
impact:

| # | Finding | Where | Impact | Severity |
|---|---|---|---|---|
| 1 | `rails_reserved_classes` retains reloadable constants | `lib/trane/controller/error_handler.rb:55-67` | development (bounded leak + behavior bug) | Medium |
| 2 | `hooks_registry` with no automatic eviction | `lib/trane.rb:108-117` | tests / multi-app | Medium-low |
| 3 | Dynamic symbols and thread-locals per `Registry::Instance` | `lib/trane/registry.rb:97,143` | tests / multi-app | Low |
| 4 | `object_id`-keyed caches with no bound or eviction | `lib/trane/registry.rb:219,230,239` | latent (unreachable from the gem today) | Low |

Recommended fix order: **1 and 3 first** — confirmed leak, small and
self-contained fix. 1 also corrects a behavior bug in development.

---

## 1. `rails_reserved_classes` retains reloadable constants

**Where:** `lib/trane/controller/error_handler.rb:55-67`

`ErrorHandler.rails_reserved_classes` memoizes `Class` objects in a gem
module-level ivar that is never invalidated:

```ruby
def self.rails_reserved_classes
  @rails_reserved_classes ||= begin
    ...
    .filter_map { |name| name.is_a?(String) ? name.safe_constantize : nil }
    .freeze
  end
end
```

If the host registers its own exception — a pattern Rails supports:
`config.action_dispatch.rescue_responses["MyApp::CustomError"] = :not_found` —
that class is autoloaded by Zeitwerk and gets pinned inside the gem.

**Evidence** (simulating a reload with `remove_const` + redefinition):

```
memo includes the original class?      true
memo size:                             15
new class is the same as the old one?  false
OLD class retained by the memo?        true
recognizes the NEW class?              false
old class still alive after GC?        true
```

**Impact.** The memory retention is **bounded** (one stale class per
host-registered exception; the `||=` never refreshes, so only the first
loaded version is retained). The side effect is worse than the memory: after
the first reload, `_trane_rails_reserved?` compares `klass <= reserved`
against the old class and returns `false`, so **the host's exception stops
being re-raised and falls into the generic 500** instead of Rails' 404. Only
affects development (production does not reload).

**Proposed fix.** Two options:

- Reset `@rails_reserved_classes` from the Engine's `to_prepare`
  (`lib/trane/engine.rb:119`), next to `Docs::Cache.invalidate!`.
- Better: don't store classes. Index by name (`String`) and compare with
  `klass.ancestors.map(&:name)`. Removes the retention at the root and makes
  invalidation unnecessary.

Note: the comment already in the code (lines 49-54) warns about calling the
method pre-boot, but doesn't cover this case — the problem isn't *when* it
memoizes but *what* it memoizes.

---

## 2. `hooks_registry` with no automatic eviction

**Where:** `lib/trane.rb:108-117`, populated from `lib/trane/engine.rb:30`

Entries are added in the Engine initializer and only leave if someone calls
`Trane.uninstall_hooks_for` by hand.

**Evidence** (2,000 apps installed, all out of scope and collectable):

```
hooks_registry.size = 2000
live Registry::Instance = 2002        slots +50017    symbols +2000
```

Each entry retains a full `ApplicationHooks` → `Registry::Instance` →
snapshot with all definitions. The key is the `object_id` (Integer), so the
app itself **can** be collected; its registry cannot.

**Impact.** In production it is 1 entry: irrelevant. The risk is in test
suites and multi-app processes. It is already documented in the code itself
and the multi-app specs clean it up
(`spec/integration/multi_app_isolation_spec.rb:11`,
`spec/integration/engine_ignore_autoload_paths_spec.rb:164,193-194`), so
today it is more a footgun for hosts than an active leak in this repo.

**Proposed fix.** None urgent. To close it: register a finalizer on the app
(`ObjectSpace.define_finalizer`) or expose the lifecycle in the README for
multi-app hosts. Cleaner alternative: don't index by `object_id` but hang the
hooks off the app itself (`app.config.trane`) — which the Engine comments
already hint at — so they die with it.

---

## 3. Dynamic symbols and thread-locals per `Registry::Instance`

**Where:** `lib/trane/registry.rb:97` and `lib/trane/registry.rb:143`

```ruby
@builder_key = :"trane_active_builder_#{object_id}"   # line 97
...
Thread.current.thread_variable_set(@builder_key, nil) # line 143 (ensure)
```

The non-obvious detail: **in Ruby 3.4, setting `nil` does not delete the
key** from the thread-locals table. Verified separately:

```ruby
t.thread_variable_set(:foo, 1);   t.thread_variables  # => [:foo]
t.thread_variable_set(:foo, nil); t.thread_variables  # => [:foo]
```

**Evidence** (5,000 instances created, `replace!`-ed and discarded):

```
thread_variables: 2 -> 5002  (delta 5000)
retained trane_active_builder keys: 5002  (all with nil value)
symbols +5000                                slots +10001
```

The instances get collected, but the dynamic symbol and the thread-locals
table entry stay alive for as long as the thread lives, after a full GC. It
grows linearly with the number of `Registry::Instance` that ran `replace!`
on that thread.

**Impact.** In production it is 1 instance per app created at boot:
irrelevant. It matters in long test suites and multi-app.

**Proposed fix.** A single **constant** key pointing to a Hash
`{ instance.object_id => builder }`, with `delete` in the `ensure`. Leaves
one symbol per process instead of one per instance, and the table empties
again.

Implementation caveat: the per-instance key exists so `active_builder`
(line 246) can tell apart builders from different instances **and** from
different threads; a flat `@active_builder` ivar won't do, because a
concurrent thread inside `register_operation` would write into another's
builder. The `object_id` indirection inside a thread-local Hash preserves
both properties.

---

## 4. `object_id`-keyed caches, with no bound or eviction (latent)

**Where:** `lib/trane/registry.rb:219` (`compiled_serializer_for`),
`:230` (`validator_field_names_for`), `:239` (`validator_declared_field_names_for`)

All three cache by `object_id` **without keeping a reference to the object**,
so the cache can never learn that its key died.

**Evidence** (fed with 100k transient objects):

```
100,000 entries × 3 caches
memsize of the Hashes = 12,583,392 bytes (not counting the values)
slots +800002
```

**Impact: latent, not active.** Today it is unreachable from the gem: every
internal caller (`Controller::Renderer`, `ContractValidator`) passes objects
owned by the frozen snapshot, and `replace!` / `reset!` / the `register_*`
paths clear all three caches — which is why measurements A and B come out
flat. But `Registry.validator_field_names_for` and
`Serializer.new(response_def, registry)` are public methods (undocumented in
the README), so a host that builds a `ResponseDefinition` per request grows
this without limit.

**Proposed fix.** Cheap and sufficient: document the invariant on the method
("current-snapshot-owned objects only") and/or add a defensive bound that
falls back to direct construction when exceeded. An `ObjectSpace::WeakMap`
would solve eviction, but it is more machinery than the case justifies.

Minor related detail: `key = [response_def.object_id, strict_mode]` allocates
an `Array` per request. Not a leak (the GC handles it, measurement A is
flat), but avoidable garbage with a nested Hash.

---

## What is healthy — do not break

These are correct, deliberate decisions; worth not losing them in a refactor:

- **`ErrorDefinition` stores `key.name` (String), not the `Class`**
  (`lib/trane/error_registry.rb:26`). Registering `error MyApp::Foo` does
  **not** pin the host's class. It is exactly the mistake finding 1 does
  make — the contrast is a useful reference for the good pattern.
- **No `to_sym` on user input**, so no symbol DoS: `_trane_operation` comes
  from the route's `defaults` (injected in `RoutingExtension`), not from
  `params`; and `ExtraAttributesFilter` caps at `MAX_VALUES = 100` and only
  calls `to_s`.
- **`ExtraAttributesFilter::EMPTY`** as a shared frozen sentinel.
- **`Docs::Cache`** keeps a single bounded snapshot, invalidated on every
  `to_prepare`.
- Definitions are frozen `Data` objects: nothing mutable shared between
  requests.

---

## How to reproduce

The measurements were made with an ad-hoc script (not checked in; see
[Pending](#pending)). Minimal version to regenerate the numbers:

```ruby
# ruby -I lib probe.rb
require "trane"
require "objspace"

def measure(label)
  4.times { GC.start(full_mark: true, immediate_sweep: true) }
  slots, syms = GC.stat[:heap_live_slots], Symbol.all_symbols.size
  yield
  4.times { GC.start(full_mark: true, immediate_sweep: true) }
  printf("%-46s slots %+9d  symbols %+7d\n",
         label, GC.stat[:heap_live_slots] - slots, Symbol.all_symbols.size - syms)
end

def build_op(name)
  Trane::OperationDefinition.new(name: name, responses: {
    200 => Trane::ResponseDefinition.new(status: 200, fields: [
      Trane::FieldNode.new(name: :id, type: :integer),
      Trane::FieldNode.new(name: :name, type: :string),
      Trane::FieldNode.new(name: :secret, type: :string, extra: true)
    ])
  })
end

data = { id: 1, name: "x", secret: "s" }

# A) steady-state request path — must come out flat
inst = Trane::Registry::Instance.new
inst.replace! { |b| b.register_operation(build_op(:show_user)) }
resp = inst.operations[:show_user].responses[200]
measure("A) 200k requests") do
  200_000.times { inst.compiled_serializer_for(resp, :raise).serialize(data) }
end

# B) reload path on the SAME instance — must come out flat
ri = Trane::Registry::Instance.new
measure("B) 5k reloads (same instance)") do
  5_000.times { ri.replace! { |b| b.register_operation(build_op(:show_user)) } }
end

# C) thread-locals + symbols leak (finding 3)
tv = Thread.current.thread_variables.size
measure("C) 5k discarded Registry::Instance") do
  5_000.times do
    i = Trane::Registry::Instance.new
    i.replace! { |b| b.register_operation(build_op(:show_user)) }
  end
end
puts "   thread_variables: #{tv} -> #{Thread.current.thread_variables.size}"
puts "   retained keys: #{Thread.current.thread_variables.grep(/trane_active_builder/).size}"

# D) hooks_registry leak (finding 2)
measure("D) 2k apps without uninstall") do
  2_000.times do
    app = Object.new
    Trane.install_hooks_for(app, Trane::ApplicationHooks.new(
      registry: Trane::Registry::Instance.new, configuration: Trane::Configuration.new))
  end
end
puts "   hooks_registry.size=#{Trane.hooks_registry.size}"
puts "   live Registry::Instance=#{ObjectSpace.each_object(Trane::Registry::Instance).count}"

# E) object_id caches with transient objects (finding 4)
p2 = Trane::Registry::Instance.new
measure("E) 100k transient fields") do
  100_000.times do
    f = [ Trane::FieldNode.new(name: :id, type: :integer) ]
    p2.validator_field_names_for(f)
    p2.compiled_serializer_for(Trane::ResponseDefinition.new(status: 200, fields: f), :raise)
  end
end
puts "   validator_field_names=#{p2.instance_variable_get(:@validator_field_names).size}"
```

Finding 1 requires Rails loaded (`require "action_controller/railtie"`),
registering `ActionDispatch::ExceptionWrapper.rescue_responses["MyApp::CustomError"]`,
calling `ErrorHandler.rails_reserved_classes`, and then doing
`remove_const` + redefining the class to simulate the reload.

---

## Pending

1. **Continuous validation tool** (second half of TODO item 8). None was
   added. Options evaluated superficially, undecided:
   - `memory_profiler` / `benchmark-memory`: good for one-off allocation
     reports over a block; they don't detect retention across cycles.
   - `derailed_benchmarks` (`perf:mem_over_time`, `perf:objects`): aimed at
     Rails apps, not a gem; it would have to run against the dummy app.
   - **Cheapest and best fit for this repo:** turn A and B from the script
     above into a spec with a slot threshold (`GC.stat[:heap_live_slots]`
     before/after, generous tolerance). Covers the regression that matters —
     that the request and reload paths stay flat — with no new dependencies.
2. Decide and implement fixes 1 through 4. None is applied: **this session
   was audit-only, no code under `lib/` was touched.**

## Out of scope (spotted in passing)

`Trane.current_hooks` takes `HOOKS_REGISTRY_MUTEX` on **every** access to
`Trane.registry` (`lib/trane.rb:108-110`), i.e. on every request. It is
global contention, not a leak — but it sits on the hot path and the
`@hooks_registry ||= {}` it protects only initializes once. Worth a look
when performance comes up.
