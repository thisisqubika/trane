# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module Trane
  # Cross-checks drawn routes against the operation registry. Two independent
  # checks, each with its own failure message:
  #   1. Every route declaring `_trane_operation` must reference a registered
  #      operation (catches typos in `contract: { operation: :x }`).
  #   2. Every such route must map to exactly one HTTP verb (a Trane operation
  #      is one verb + one path). Rails collapses `via: [:patch, :put]` into a
  #      single route whose #verb is "PATCH|PUT"; a `match` with no verb (or
  #      `via: :all`) yields a blank verb matching any method. Both are rejected.
  #
  # Pure `(routes, registry)` function — no Rails::Application coupling — so it
  # can be exercised with fake route doubles in unit specs and with a real
  # route set from the Engine or the `trane:check` rake task.
  class RouteValidator
    # @param routes [Enumerable] route objects responding to #verb, #defaults, #path
    # @param registry [Module, Trane::Registry::Instance] responds to #operations
    # @raise [Trane::RoutingContractError] on an unregistered operation or a multi/any-verb route
    def self.validate!(routes, registry)
      validate_operations_registered!(routes, registry)
      validate_single_verb!(routes)
    end

    class << self
      private

      def validate_operations_registered!(routes, registry)
        orphans = {}

        routes.each do |route|
          op = route.defaults[:_trane_operation]
          next if op.blank?
          next if registry.operations.key?(op.to_sym)

          orphans[op] ||= route
        end

        return if orphans.empty?

        operation_names = registry.operations.keys
        details = orphans.map do |op, route|
          suggestion = Trane.spelling_suggestion(op, operation_names)
          line = "#{describe_route(route)} references operation :#{op}, but no such operation is registered"
          line += " (did you mean :#{suggestion}?)" if suggestion
          line
        end

        raise Trane::RoutingContractError, "Trane route/registry cross-check failed:\n  #{details.join("\n  ")}"
      end

      def validate_single_verb!(routes)
        offenders = {}

        routes.each do |route|
          op = route.defaults[:_trane_operation]
          next if op.blank?
          next if single_http_verb?(route.verb)

          offenders[op] ||= route
        end

        return if offenders.empty?

        details = offenders.map { |op, route| "#{describe_route(route)} → operation :#{op}" }
        raise Trane::RoutingContractError,
              "Trane: each route with a contract: must map to exactly one HTTP verb, " \
              "but these map to multiple verbs (or to any verb):\n  #{details.join("\n  ")}\n  " \
              "Split into separate operations or pick a single verb."
      end

      # Rails 8.1 exposes #verb as a String ("GET", "PATCH|PUT", or "" for ANY).
      # `verb.to_s` also handles the Regexp form older Rails versions expose:
      # its #to_s carries the "|" for multi-verb alternations.
      def single_http_verb?(verb)
        s = verb.to_s
        !s.strip.empty? && !s.include?("|")
      end

      def describe_route(route)
        verb = route.verb
        verb = "ANY" if verb.blank?
        "#{verb} #{route.path.spec}"
      end
    end
  end
end
