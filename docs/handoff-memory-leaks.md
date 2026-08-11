# Handoff — auditoría de memory leaks

**Fecha:** 2026-08-11
**Rama:** `init_2` (base: `a443db2`)
**Alcance:** todo `lib/` (~2.333 LOC). Cubre el ítem 8 de `docs/TODO.md`
(«revisa posibles memory leaks»); la segunda mitad de ese ítem —agregar una
herramienta que lo valide de forma continua— **quedó pendiente**, ver
[Pendientes](#pendientes).
**Entorno de medición:** Ruby 3.4.6, Rails 8.1.3.1, arm64-darwin24.

---

## Resumen

El camino caliente **no tiene fugas**. El diseño de snapshot inmutable con
invalidación de cachés en cada `replace!` funciona: 200k requests dejaron +40
slots vivos y 5k ciclos de reload dejaron +44 slots, ambos tras GC completo.

Se encontraron **4 fugas reales, ninguna en el camino de request de
producción**. Ordenadas por impacto:

| # | Hallazgo | Dónde | Impacto | Severidad |
|---|---|---|---|---|
| 1 | `rails_reserved_classes` retiene constantes recargables | `lib/trane/controller/error_handler.rb:55-67` | development (fuga acotada + bug de comportamiento) | Media |
| 2 | `hooks_registry` sin eviction automática | `lib/trane.rb:108-117` | tests / multi-app | Media-baja |
| 3 | Símbolos dinámicos y thread-locals por `Registry::Instance` | `lib/trane/registry.rb:97,143` | tests / multi-app | Baja |
| 4 | Cachés keyed por `object_id` sin tope ni eviction | `lib/trane/registry.rb:219,230,239` | latente (inalcanzable desde el gem hoy) | Baja |

Recomendación de orden de arreglo: **1 y 3 primero** — fuga confirmada, arreglo
chico y acotado. El 1 además corrige un bug de comportamiento en development.

---

## 1. `rails_reserved_classes` retiene constantes recargables

**Dónde:** `lib/trane/controller/error_handler.rb:55-67`

`ErrorHandler.rails_reserved_classes` memoiza objetos `Class` en un ivar a nivel
de módulo del gem, que nunca se invalida:

```ruby
def self.rails_reserved_classes
  @rails_reserved_classes ||= begin
    ...
    .filter_map { |name| name.is_a?(String) ? name.safe_constantize : nil }
    .freeze
  end
end
```

Si el host registra su propia excepción —patrón soportado por Rails:
`config.action_dispatch.rescue_responses["MyApp::CustomError"] = :not_found`—
esa clase es autoloadeada por Zeitwerk y queda pinneada en el gem.

**Evidencia** (simulando un reload con `remove_const` + redefinición):

```
memo incluye la clase original?       true
tamaño del memo:                      15
clase nueva es la misma que la vieja? false
clase VIEJA retenida por el memo?     true
reconoce la clase NUEVA?              false
clase vieja sigue viva tras GC?       true
```

**Impacto.** La retención de memoria es **acotada** (una clase obsoleta por
excepción registrada por el host; el `||=` nunca refresca, así que retiene solo
la primera versión cargada). El efecto colateral es peor que la memoria: tras el
primer reload, `_trane_rails_reserved?` compara `klass <= reserved` contra la
clase vieja y da `false`, así que **la excepción del host deja de re-lanzarse y
cae en el 500 genérico** en vez del 404 de Rails. Solo afecta a development
(producción no recarga).

**Arreglo propuesto.** Dos opciones:

- Resetear `@rails_reserved_classes` desde el `to_prepare` del Engine
  (`lib/trane/engine.rb:119`), junto a `Docs::Cache.invalidate!`.
- Mejor: no guardar clases. Indexar por nombre (`String`) y comparar con
  `klass.ancestors.map(&:name)`. Elimina la retención de raíz y hace innecesaria
  la invalidación.

Nota: el comentario que ya está en el código (líneas 49-54) advierte sobre
llamar al método pre-boot, pero no cubre este caso — el problema no es *cuándo*
se memoiza sino *qué* se memoiza.

---

## 2. `hooks_registry` sin eviction automática

**Dónde:** `lib/trane.rb:108-117`, poblado desde `lib/trane/engine.rb:30`

Las entradas se agregan en el initializer del Engine y solo salen si alguien
llama `Trane.uninstall_hooks_for` a mano.

**Evidencia** (2.000 apps instaladas, todas fuera de scope y recolectables):

```
hooks_registry.size = 2000
Registry::Instance vivas = 2002        slots +50017    símbolos +2000
```

Cada entrada retiene un `ApplicationHooks` completo → `Registry::Instance` →
snapshot con todas las definiciones. La clave es el `object_id` (Integer), así
que la app en sí **sí** se puede recolectar; su registry no.

**Impacto.** En producción es 1 entrada: irrelevante. El riesgo está en suites
de tests y procesos multi-app. Ya está documentado en el propio código y los
specs de multi-app lo limpian (`spec/integration/multi_app_isolation_spec.rb:11`,
`spec/integration/engine_ignore_autoload_paths_spec.rb:164,193-194`), así que
hoy es más un footgun para hosts que una fuga activa en este repo.

**Arreglo propuesto.** Ninguno urgente. Si se quiere cerrar: registrar un
finalizer sobre la app (`ObjectSpace.define_finalizer`) o exponer el ciclo de
vida en el README para hosts multi-app. Alternativa más limpia: no indexar por
`object_id` sino colgar los hooks de la propia app
(`app.config.trane`) — lo que ya se insinúa en los comentarios del Engine — de
modo que mueran con ella.

---

## 3. Símbolos dinámicos y thread-locals por `Registry::Instance`

**Dónde:** `lib/trane/registry.rb:97` y `lib/trane/registry.rb:143`

```ruby
@builder_key = :"trane_active_builder_#{object_id}"   # línea 97
...
Thread.current.thread_variable_set(@builder_key, nil) # línea 143 (ensure)
```

El detalle no obvio: **en Ruby 3.4, poner `nil` no borra la clave** de la tabla
de thread-locals. Verificado aparte:

```ruby
t.thread_variable_set(:foo, 1);   t.thread_variables  # => [:foo]
t.thread_variable_set(:foo, nil); t.thread_variables  # => [:foo]
```

**Evidencia** (5.000 instancias creadas, `replace!`-adas y descartadas):

```
thread_variables: 2 -> 5002  (delta 5000)
claves trane_active_builder retenidas: 5002  (todas con valor nil)
símbolos +5000                                slots +10001
```

Las instancias se recolectan, pero el símbolo dinámico y la entrada en la tabla
de thread-locals quedan vivos mientras viva el thread, tras GC completo. Crece
linealmente con la cantidad de `Registry::Instance` que hayan corrido `replace!`
en ese thread.

**Impacto.** En producción es 1 instancia por app creada en boot: irrelevante.
Importa en suites largas y multi-app.

**Arreglo propuesto.** Una única clave **constante** que apunte a un `Hash`
`{ instance.object_id => builder }`, con `delete` en el `ensure`. Deja un solo
símbolo por proceso en vez de uno por instancia, y la tabla vuelve a vaciarse.

Ojo al implementarlo: la clave por-instancia existe para que `active_builder`
(línea 246) distinga builders de instancias distintas **y** de threads
distintos; un ivar plano `@active_builder` no sirve, porque un thread
concurrente en `register_operation` escribiría en el builder de otro. La
indirección por `object_id` dentro de un Hash thread-local preserva ambas
propiedades.

---

## 4. Cachés keyed por `object_id`, sin tope ni eviction (latente)

**Dónde:** `lib/trane/registry.rb:219` (`compiled_serializer_for`),
`:230` (`validator_field_names_for`), `:239` (`validator_declared_field_names_for`)

Las tres cachean por `object_id` **sin guardar referencia al objeto**, así que la
caché nunca puede saber que su clave murió.

**Evidencia** (alimentadas con 100k objetos transitorios):

```
100.000 entradas × 3 cachés
memsize de los Hash = 12.583.392 bytes (sin contar los valores)
slots +800002
```

**Impacto: latente, no activo.** Hoy es inalcanzable desde el gem: todos los
callers internos (`Controller::Renderer`, `ContractValidator`) pasan objetos
dueños del snapshot congelado, y `replace!` / `reset!` / los `register_*` limpian
las tres cachés — de ahí que las mediciones A y B den planas. Pero
`Registry.validator_field_names_for` y `Serializer.new(response_def, registry)`
son métodos públicos (no documentados en el README), así que un host que
construya un `ResponseDefinition` por request hace crecer esto sin límite.

**Arreglo propuesto.** Barato y suficiente: documentar la invariante en el
método («solo objetos dueños del snapshot actual») y/o poner un tope defensivo
con corte a la construcción directa cuando se excede. Un `ObjectSpace::WeakMap`
resolvería la eviction, pero es más maquinaria de la que el caso justifica.

Detalle menor asociado: `key = [response_def.object_id, strict_mode]` aloca un
`Array` por request. No es fuga (el GC lo maneja, medición A plana), pero es
garbage evitable con un Hash anidado.

---

## Lo que está sano — no romper

Estos puntos son decisiones correctas y deliberadas; conviene no perderlas en un
refactor:

- **`ErrorDefinition` guarda `key.name` (String), no la `Class`**
  (`lib/trane/error_registry.rb:26`). Registrar `error MyApp::Foo` **no** pinnea
  la clase del host. Es exactamente el error que sí comete el hallazgo 1 — el
  contraste vale como referencia de cuál es el patrón bueno.
- **Sin `to_sym` sobre input del usuario**, así que no hay DoS por símbolos:
  `_trane_operation` viene de los `defaults` de la ruta (inyectados en
  `RoutingExtension`), no de `params`; y `ExtraAttributesFilter` topea en
  `MAX_VALUES = 100` y solo hace `to_s`.
- **`ExtraAttributesFilter::EMPTY`** como sentinela congelado compartido.
- **`Docs::Cache`** mantiene un único snapshot acotado, invalidado en cada
  `to_prepare`.
- Las definiciones son objetos `Data` congelados: nada mutable compartido entre
  requests.

---

## Cómo reproducir

Las mediciones se hicieron con un script ad-hoc (no quedó versionado; ver
[Pendientes](#pendientes)). Versión mínima para regenerar los números:

```ruby
# ruby -I lib probe.rb
require "trane"
require "objspace"

def measure(label)
  4.times { GC.start(full_mark: true, immediate_sweep: true) }
  slots, syms = GC.stat[:heap_live_slots], Symbol.all_symbols.size
  yield
  4.times { GC.start(full_mark: true, immediate_sweep: true) }
  printf("%-46s slots %+9d  símbolos %+7d\n",
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

# A) camino de request en estado estable — debe dar plano
inst = Trane::Registry::Instance.new
inst.replace! { |b| b.register_operation(build_op(:show_user)) }
resp = inst.operations[:show_user].responses[200]
measure("A) 200k requests") do
  200_000.times { inst.compiled_serializer_for(resp, :raise).serialize(data) }
end

# B) camino de reload sobre la MISMA instancia — debe dar plano
ri = Trane::Registry::Instance.new
measure("B) 5k reloads (misma instancia)") do
  5_000.times { ri.replace! { |b| b.register_operation(build_op(:show_user)) } }
end

# C) fuga de thread-locals + símbolos (hallazgo 3)
tv = Thread.current.thread_variables.size
measure("C) 5k Registry::Instance descartadas") do
  5_000.times do
    i = Trane::Registry::Instance.new
    i.replace! { |b| b.register_operation(build_op(:show_user)) }
  end
end
puts "   thread_variables: #{tv} -> #{Thread.current.thread_variables.size}"
puts "   claves retenidas: #{Thread.current.thread_variables.grep(/trane_active_builder/).size}"

# D) fuga de hooks_registry (hallazgo 2)
measure("D) 2k apps sin uninstall") do
  2_000.times do
    app = Object.new
    Trane.install_hooks_for(app, Trane::ApplicationHooks.new(
      registry: Trane::Registry::Instance.new, configuration: Trane::Configuration.new))
  end
end
puts "   hooks_registry.size=#{Trane.hooks_registry.size}"
puts "   Registry::Instance vivas=#{ObjectSpace.each_object(Trane::Registry::Instance).count}"

# E) cachés object_id con objetos transitorios (hallazgo 4)
p2 = Trane::Registry::Instance.new
measure("E) 100k fields transitorios") do
  100_000.times do
    f = [ Trane::FieldNode.new(name: :id, type: :integer) ]
    p2.validator_field_names_for(f)
    p2.compiled_serializer_for(Trane::ResponseDefinition.new(status: 200, fields: f), :raise)
  end
end
puts "   validator_field_names=#{p2.instance_variable_get(:@validator_field_names).size}"
```

Para el hallazgo 1 hace falta Rails cargado (`require "action_controller/railtie"`),
registrar `ActionDispatch::ExceptionWrapper.rescue_responses["MyApp::CustomError"]`,
llamar a `ErrorHandler.rails_reserved_classes`, y después hacer
`remove_const` + redefinir la clase para simular el reload.

---

## Pendientes

1. **Herramienta de validación continua** (segunda mitad del ítem 8 del TODO).
   No se agregó ninguna. Opciones evaluadas por encima, sin decidir:
   - `memory_profiler` / `benchmark-memory`: buenos para reportes puntuales de
     allocation en un bloque; no detectan retención entre ciclos.
   - `derailed_benchmarks` (`perf:mem_over_time`, `perf:objects`): apuntado a
     apps Rails, no a una gema; requeriría correrlo sobre la dummy app.
   - **Lo más barato y ajustado a este repo:** convertir A y B del script de
     arriba en un spec con umbral de slots (`GC.stat[:heap_live_slots]` antes/
     después, tolerancia holgada). Cubre la regresión que importa —que el camino
     de request y el de reload sigan planos— sin dependencias nuevas.
2. Decidir e implementar los arreglos 1 a 4. Ninguno está aplicado: **esta
   sesión fue solo auditoría, no se tocó código de `lib/`.**

## Fuera de alcance (detectado de paso)

`Trane.current_hooks` toma `HOOKS_REGISTRY_MUTEX` en **cada** acceso a
`Trane.registry` (`lib/trane.rb:108-110`), o sea en cada request. Es contención
global, no una fuga — pero está en el camino caliente y el `@hooks_registry ||= {}`
que protege solo se inicializa una vez. Vale mirarlo cuando se toque
performance.
