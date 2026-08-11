# gemfiles/

Un `Gemfile` por versión minor de Rails soportada (ver la tabla "Supported versions"
en el [README](../README.md)). El job `gem` de CI (`.github/workflows/ci.yml`) corre
la suite contra cada uno, seleccionando el archivo vía `BUNDLE_GEMFILE`, cruzado con
cada versión de Ruby soportada.

Los `.gemfile.lock` de este directorio **no se versionan** (están en `.gitignore`).
Ruby sí cambia qué versiones de dependencias transitivas se resuelven: por ejemplo,
gemas usadas solo en dev/test como `rubocop` arrastran dependencias (`parallel`,
etc.) que suben su piso mínimo de Ruby con el tiempo. Un `.lock` generado con una
versión de Ruby puede fijar una versión de esa dependencia que no es instalable en
un Ruby más viejo del que también decimos soportar — y como `ruby/setup-ruby` corre
`bundle install` en modo `deployment` cuando encuentra un lock ya commiteado, ese
modo no permite re-resolver, así que la instalación falla en vez de bajar de versión
en silencio.

Por eso cada celda de la matriz (Ruby × Rails) resuelve su propio lock en el momento,
sin arrastrar el de otra versión de Ruby. `bundler-cache: true` sigue cacheando
`vendor/bundle` entre corridas usando ese lock generado como parte de la key.

## Agregar una nueva versión de Rails a la matriz

1. Crear `gemfiles/rails_X_Y.gemfile` copiando la estructura de uno existente.
2. Correr `BUNDLE_GEMFILE=gemfiles/rails_X_Y.gemfile bundle install` localmente para
   confirmar que resuelve sin conflictos (el `.lock` que genera es solo para
   chequear localmente — no se commitea).
3. Agregar `rails_X_Y` a la matriz `rails:` en `.github/workflows/ci.yml`.
4. Actualizar la tabla "Supported versions" del README y el bound superior en `trane.gemspec` si corresponde.
