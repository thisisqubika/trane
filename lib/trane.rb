# frozen_string_literal: true

module Trane
  class Error < StandardError; end

  # Raised when a route's `contract:` metadata is malformed (unknown key,
  # missing/blank :operation) or when a route's declared operation has no
  # matching entry in the registry. Fails loud at boot/draw time instead of
  # deferring the mistake to request time.
  class RoutingContractError < Error; end
end

require_relative "trane/version"
require_relative "trane/configuration"
require_relative "trane/types"
require_relative "trane/field_node"
require_relative "trane/field_builder"
require_relative "trane/param_definition"
require_relative "trane/operation_definition"
require_relative "trane/representation_definition"
require_relative "trane/error_registry"
require_relative "trane/registry"
require_relative "trane/application_hooks"
require_relative "trane/serializer"
require_relative "trane/extra_attributes_filter"
require_relative "trane/boot_validator"
require_relative "trane/route_validator"
require_relative "trane/contract_validator"
require_relative "trane/controller"
require_relative "trane/routing_extension"

module Trane
  THREAD_LOCAL_HOOKS_KEY = :trane_explicit_hooks
  CLAIM_MUTEX = Mutex.new

  def self.configure
    yield configuration
  end

  # Returns the current application's Configuration instance.
  def self.configuration
    current_hooks.configuration
  end

  # Returns the current application's Registry::Instance.
  def self.registry
    current_hooks.registry
  end

  # Returns the ApplicationHooks for the current Rails application. When
  # no Rails.application is present (pre-boot, console, rake) returns
  # the process-level default hooks shared by single-app deployments.
  def self.current_hooks
    explicit = Thread.current.thread_variable_get(THREAD_LOCAL_HOOKS_KEY)
    return explicit if explicit

    if defined?(Rails) && Rails.application
      hooks = hooks_registry[Rails.application.object_id]
      return hooks if hooks
      warn_default_hooks_fallback
      default_hooks
    else
      default_hooks
    end
  end

  # Returns (memoizing) the process-level default ApplicationHooks instance.
  # This is the hooks object used by the first Rails application booted in
  # the process so that pre-boot DSL registrations are preserved.
  def self.default_hooks
    @default_hooks ||= ApplicationHooks.new(
      registry:      Registry::Instance.new,
      configuration: Configuration.new
    )
  end

  # Emits a one-time warning when Trane.current_hooks falls back to
  # default_hooks despite Rails.application being set. This usually means
  # the Engine initializer did not run for that app — a real bug surface
  # worth surfacing without breaking single-app behaviour.
  def self.warn_default_hooks_fallback
    return if @warned_default_fallback
    @warned_default_fallback = true
    msg = "[Trane] current_hooks falling back to default_hooks for #{Rails.application.class.name}; " \
          "the Engine's trane.install_application_hooks initializer may not have run for this app."
    if defined?(Rails.logger) && Rails.logger
      Rails.logger.warn(msg)
    else
      warn(msg)
    end
  end

  # Internal — per-application hooks storage keyed by Rails::Application
  # object_id. Public callers should use install_hooks_for / hooks_for /
  # uninstall_hooks_for / with_application instead of touching this Hash
  # directly. Isolated from Rails::Railtie::Configuration's shared @@options
  # so anonymous Rails::Application subclasses get truly separate hooks.
  def self.hooks_registry
    @hooks_registry ||= {}
  end

  # Installs ApplicationHooks for a given Rails application instance,
  # keyed by the application's object_id for true per-instance isolation.
  def self.install_hooks_for(rails_app, hooks)
    hooks_registry[rails_app.object_id] = hooks
  end

  # Returns the ApplicationHooks registered for a given Rails application,
  # or nil if none have been installed.
  def self.hooks_for(rails_app)
    hooks_registry[rails_app.object_id]
  end

  # Removes the ApplicationHooks registered for a given Rails application.
  # Use this in test teardown to prevent the hooks_registry from growing
  # unboundedly when tests create anonymous Rails::Application subclasses.
  def self.uninstall_hooks_for(rails_app)
    hooks_registry.delete(rails_app.object_id)
  end

  # Atomically installs hooks for a Rails application via the Engine
  # initializer. The first app booted in the process claims the gem's
  # default hooks (preserving pre-boot DSL registrations); subsequent
  # apps get fresh, isolated hook pairs. CLAIM_MUTEX makes the claim
  # decision race-free under concurrent boot.
  def self.install_hooks_for_app(rails_app)
    CLAIM_MUTEX.synchronize do
      return hooks_registry[rails_app.object_id] if hooks_registry.key?(rails_app.object_id)

      hooks = if @default_hooks_claimed
        ApplicationHooks.new(
          registry:      Registry::Instance.new,
          configuration: Configuration.new
        )
      else
        @default_hooks_claimed = true
        default_hooks
      end
      hooks_registry[rails_app.object_id] = hooks
    end
  end

  # Scopes Trane DSL and lookup calls inside the block to the given
  # Rails application's hooks. Intended for multi-application scripts,
  # specs, and rake tasks that need to address a specific app explicitly.
  def self.with_application(rails_app)
    # Capture prior before any raise so the ensure block doesn't clobber an
    # outer with_application frame's hooks if hooks_for(rails_app) returns nil.
    prior = Thread.current.thread_variable_get(THREAD_LOCAL_HOOKS_KEY)
    set_thread_hooks = false

    hooks = hooks_for(rails_app)
    raise Trane::Error, "Trane: application has no Trane hooks installed; the Engine initializer must have run" unless hooks

    Thread.current.thread_variable_set(THREAD_LOCAL_HOOKS_KEY, hooks)
    set_thread_hooks = true
    yield
  ensure
    Thread.current.thread_variable_set(THREAD_LOCAL_HOOKS_KEY, prior) if set_thread_hooks
  end

  def self.operation(name, &block)
    builder = OperationBuilder.new(name)
    builder.instance_eval(&block)
    registry.register_operation(builder.build)
  end

  def self.representation(name, &block)
    builder = RepresentationBuilder.new(name)
    builder.instance_eval(&block)
    registry.register_representation(builder.build)
  end

  def self.errors(&block)
    builder = ErrorsBuilder.new
    builder.instance_eval(&block)
    builder.definitions.each { |d| registry.register_error(d) }
  end

  # Returns the closest spelling match for term among candidates, or nil
  # when no candidate is close enough. Backs the "Did you mean?" hints in
  # both the routing contract: hash validator and the route/registry
  # cross-check, so the two validations never drift on suggestion logic.
  def self.spelling_suggestion(term, candidates)
    require "did_you_mean"
    DidYouMean::SpellChecker.new(dictionary: candidates.map(&:to_s)).correct(term.to_s).first
  end
end

require_relative "trane/docs/service_definition"
require_relative "trane/docs/html_renderer"
require_relative "trane/docs/cache"

if defined?(Rails::Engine)
  require_relative "trane/engine"
end
