# frozen_string_literal: true

require "trane/routing_extension"
require "trane/docs/app"

module Trane
  class Engine < ::Rails::Engine
    isolate_namespace Trane

    # Install per-application Trane hooks (registry + configuration) on
    # this Rails::Application's config slot before host initializers run.
    # The first Rails application booted in the process reuses the gem's
    # process-level default hooks so pre-Engine writes (e.g. unit specs
    # that call Trane.operation before Rails boots) are preserved. Any
    # subsequent application booted in the same process gets a fresh,
    # isolated pair.
    #
    # Must run before trane.ignore_autoload_paths so that Trane.configuration
    # resolves to the per-app hooks (not the global default_hooks) when
    # _set_contracts_paths! is called. Running both at before: :set_autoload_paths
    # with an explicit after: dependency guarantees this order even in multi-app
    # scenarios where default_hooks may already be frozen.
    #
    # NOTE: The to_prepare block and freeze_configuration initializer below
    # intentionally route through the Trane::Registry / Trane::Configuration
    # module-level shims (rather than app.config.trane.registry directly) to
    # preserve mock compatibility in engine_to_prepare_error_context_spec.rb.
    # If you ever change them to bypass the shim, update that spec accordingly.
    initializer "trane.install_application_hooks", before: :set_autoload_paths do |app|
      Trane.install_hooks_for_app(app) unless Trane.hooks_for(app)
    end

    # Tell Zeitwerk to ignore all contracts paths in the host application.
    # Files there are DSL declarations (Trane.operation, Trane.representation,
    # Trane.errors) that do not define Ruby constants. Without this ignore,
    # Rails' eager_load in production would crash with
    # "expected file ... to define constant ..." — see README "Autoloading note".
    #
    # Hosts override the paths via `config.trane.contracts_paths = [...]` in
    # `config/application.rb` (NOT in config/initializers/trane.rb — too late).
    #
    # Runs after trane.install_application_hooks so Trane.configuration resolves
    # to the per-app hooks before _set_contracts_paths! is called.
    initializer "trane.ignore_autoload_paths",
                before: :set_autoload_paths,
                after: "trane.install_application_hooks" do |app|
      raw_paths = (app.config.respond_to?(:trane) &&
                   app.config.trane.respond_to?(:contracts_paths) &&
                   app.config.trane.contracts_paths) ||
                  Trane::Configuration::DEFAULT_CONTRACTS_PATHS

      Trane.configuration._set_contracts_paths!(raw_paths)

      raw_paths.each do |entry|
        pn  = entry.is_a?(Pathname) ? entry : Pathname.new(entry)
        abs = pn.absolute? ? pn : app.root.join(pn)
        next unless abs.exist?

        begin
          abs_str = abs.realpath.to_s
          Rails.autoloaders.main.ignore(abs_str) if Rails.autoloaders.main
          Rails.autoloaders.once.ignore(abs_str) if Rails.autoloaders.once
        rescue Errno::ENOENT
          next
        end
      end
    end

    # Prepends Trane::RoutingExtension onto ActionDispatch::Routing::Mapper so
    # the `contract:` keyword is available in every `routes.draw` block, with
    # no wrapper required. `before: :add_routing_paths` guarantees the prepend
    # is active before Rails draws any route. `Module#prepend` is idempotent,
    # so re-running this initializer (e.g. multiple anonymous Rails::Application
    # instances in specs) does not duplicate the entry in ancestors.
    initializer "trane.prepend_routing_extension", before: :add_routing_paths do
      ActionDispatch::Routing::Mapper.prepend(Trane::RoutingExtension)
    end

    # Freeze Trane::Configuration after the host's initializers have run.
    # Prevents post-boot mutation in multi-threaded servers (Puma, Falcon).
    # Hosts must do all config in config/initializers/trane.rb.
    #
    # Ordering: this runs in the Engine batch (after: :load_config_initializers),
    # which completes before Rails' Finisher batch. The Finisher's
    # :set_routes_reloader_hook triggers route drawing — meaning
    # Configuration is always frozen by the time host routes are drawn.
    initializer "trane.freeze_configuration", after: :load_config_initializers do
      Trane::Configuration.instance.freeze!
    end

    # Cross-check every drawn route's `_trane_operation` against the
    # registry so a typo that survives Validation A (a well-formed
    # `contract:` hash pointing at a nonexistent operation) fails at boot
    # instead of at request time.
    #
    # Ordering: routes are NOT guaranteed drawn by `to_prepare` or
    # `after_initialize` — they are only drawn (eagerly) once the Finisher
    # reaches `set_routes_reloader_hook`. Running `after:` that hook is the
    # earliest point where `app.routes.routes` is reliably populated, and
    # only when `config.eager_load` is true (otherwise route drawing is
    # lazy and deferred to first request/`reload_routes_unless_loaded`,
    # which `trane:check` triggers explicitly post-boot).
    initializer "trane.validate_route_contracts", after: :set_routes_reloader_hook do |app|
      next unless app.config.eager_load

      Trane.with_application(app) do
        Trane::RouteValidator.validate!(app.routes.routes, Trane.registry)
      end
    end

    # Auto-load contract definition files and validate on each prepare.
    # Each of the three steps (registry reload, boot validation, docs
    # precompute) is wrapped to add actionable context to any failure
    # while preserving the original exception via `cause:`.
    #
    # Loading order across all contracts_paths:
    #   Phase 1 — every errors.rb from every base path (in declaration order).
    #   Phase 2 — all other .rb files from every base path (sorted within each).
    config.to_prepare do
      if defined?(Rails.root) && Rails.root
        last_loaded_file = nil

        begin
          Trane::Registry.replace! do |_builder|
            contracts_paths = Trane.configuration.contracts_paths

            contracts_paths.each do |relative_path|
              errors_file = Rails.root.join(relative_path, "errors.rb")
              if errors_file.exist?
                last_loaded_file = errors_file.to_s
                load errors_file
              end
            end

            contracts_paths.each do |relative_path|
              errors_file = Rails.root.join(relative_path, "errors.rb").to_s
              Dir[Rails.root.join(relative_path, "**/*.rb")].sort.each do |f|
                next if f == errors_file
                last_loaded_file = f
                load f
              end
            end
          end
        rescue Trane::Error
          raise
        rescue ScriptError, StandardError => e
          raise Trane::Error,
                "Trane: failed to load contract files in to_prepare. " \
                "Last attempted file: #{last_loaded_file || '(none — pre-load setup)'}. " \
                "Original: #{e.class}: #{e.message}",
                cause: e
        end

        if defined?(Trane::BootValidator) && Rails.application.config.eager_load
          begin
            Trane::Registry.validate!
          rescue Trane::Error
            raise
          rescue StandardError => e
            raise Trane::Error,
                  "Trane: BootValidator raised an unexpected error type during to_prepare. " \
                  "Original: #{e.class}: #{e.message}",
                  cause: e
          end
        end

        if defined?(Trane::Docs::Cache)
          # The host routes are NOT drawn during to_prepare: it runs before the
          # Finisher's set_routes_reloader_hook in EVERY environment (confirmed
          # empirically — the route set is empty here even under eager_load).
          # Precomputing the docs now would build a snapshot from an empty route
          # set, so every operation would fall back to method "GET" with an empty
          # path. Instead we invalidate; the first post-boot read (inside a
          # request, with the routes drawn) computes the correct snapshot lazily
          # via Cache.ensure_snapshot. In development to_prepare also runs on each
          # reload, so this keeps the cache fresh after contract/route changes.
          Trane::Docs::Cache.invalidate!
        end
      else
        Trane::Registry.reset!
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/trane.rake", __dir__)
    end
  end
end
