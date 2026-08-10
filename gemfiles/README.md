# gemfiles/

Un `Gemfile` por versión minor de Rails soportada (ver la tabla "Supported versions"
en el [README](../README.md)). El job `gem` de CI (`.github/workflows/ci.yml`) corre
la suite contra cada uno, seleccionando el archivo vía `BUNDLE_GEMFILE`.

Las versiones de Ruby de la matriz **no** requieren un Gemfile propio: Ruby es sólo
el intérprete que ejecuta Bundler, no cambia qué dependencias se resuelven.

## Mantenimiento

No hay ningún bot ni step de CI que regenere estos archivos. Son manuales: si
tocás dependencias en `../Gemfile` o `../trane.gemspec` (agregar, quitar, cambiar
bounds), tenés que regenerar el lock de cada variante y commitearlo junto con el
cambio:

```bash
bundle install                                          # Gemfile raíz
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_8_1.gemfile bundle install
```

Si esto empieza a resultar tedioso (por ejemplo, al agregar más versiones de Rails
a la matriz), considerar migrar a la gema [`appraisal`](https://github.com/thoughtbot/appraisal),
que genera estos archivos a partir de un único `Appraisals` en la raíz.

## Agregar una nueva versión de Rails a la matriz

1. Crear `gemfiles/rails_X_Y.gemfile` copiando la estructura de uno existente.
2. Correr `BUNDLE_GEMFILE=gemfiles/rails_X_Y.gemfile bundle install` para generar su lock.
3. Agregar `rails_X_Y` a la matriz `rails:` en `.github/workflows/ci.yml`.
4. Actualizar la tabla "Supported versions" del README y el bound superior en `trane.gemspec` si corresponde.
