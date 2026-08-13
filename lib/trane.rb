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
require_relative "trane/serializer"
require_relative "trane/extra_attributes_filter"
require_relative "trane/boot_validator"
require_relative "trane/route_validator"
require_relative "trane/contract_validator"
require_relative "trane/controller"
require_relative "trane/routing_extension"

module Trane
  # Process-level Trane state. Trane supports exactly one Rails application
  # per Ruby process — the standard Rails deployment model. The registry and
  # configuration are created eagerly at require time so pre-boot DSL
  # registrations (e.g. unit specs calling Trane.operation before Rails
  # boots) land in the same objects the booted application later uses.
  @registry      = Registry::Instance.new
  @configuration = Configuration.new

  def self.configure
    yield configuration
  end

  # Returns the process-level Configuration.
  def self.configuration
    @configuration
  end

  # Returns the process-level Registry::Instance.
  def self.registry
    @registry
  end

  # Restores Trane to a pristine state: empties the registry (snapshot and
  # derived caches), clears the configuration (values and frozen flag), and
  # invalidates the docs cache. Intended for test suites that need isolation
  # between examples or that boot throwaway Rails applications.
  def self.reset!
    registry.reset!
    configuration.reset!
    Docs::Cache.invalidate! if defined?(Docs::Cache)
    nil
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
