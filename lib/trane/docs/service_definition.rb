# frozen_string_literal: true

require "time"

module Trane
  module Docs
    class ServiceDefinition
      # Generate a complete service definition hash from the registry and routes.
      #
      # @param routes [ActionDispatch::Routing::RouteSet::NamedRouteCollection, Array] Rails routes
      # @param service_name [String] published as `service.name`. Trane does not
      #   configure the API name: callers inside a Rails application pass
      #   `Rails.application.name`. Required — there is no default.
      # @return [Hash]
      def self.generate(routes, service_name:)
        new(routes, service_name: service_name).to_h
      end

      def initialize(routes, service_name:)
        @routes       = routes
        @service_name = service_name
        @registry     = Trane.current_hooks.registry
      end

      def to_h
        {
          service: {
            name: @service_name
          },
          operations: build_operations,
          representations: build_representations,
          errors: build_errors
        }
      end

      private

      def build_operations
        route_map = extract_route_map

        @registry.operations.map do |name, op|
          route_info = route_map[name.to_s] || {}

          entry = {
            id: name.to_s,
            summary: op.summary,
            method: route_info[:method] || "GET",
            path: route_info[:path] || ""
          }

          entry[:request] = build_request(op.request) if op.request
          entry[:responses] = build_responses(op.responses)
          entry[:errors] = op.error_keys.map(&:to_s) unless op.error_keys.empty?

          entry
        end
      end

      def build_request(request_def)
        result = {}

        unless request_def.params.empty?
          result[:params] = request_def.params.map do |p|
            entry = { name: p.name.to_s, type: p.type.to_s, location: p.location.to_s, required: p.required }
            entry[:enum] = serialize_enum(p.enum) unless p.enum.nil?
            entry
          end
        end

        unless request_def.body_fields.empty?
          result[:body] = build_field_list(request_def.body_fields)
        end

        result
      end

      def build_responses(responses)
        responses.map do |status, resp|
          { status: status, fields: build_field_list(resp.fields) }
        end
      end

      def build_field_list(fields)
        fields.map { |f| build_field_hash(f) }
      end

      def build_field_hash(field)
        entry = { name: field.name.to_s }
        entry[:type] = field.type.to_s if field.type
        entry[:format] = field.format.to_s if field.format
        entry[:extra] = true if field.extra
        entry[:array_of] = field.array_of.to_s if field.array_of
        entry[:required] = field.required unless field.required.nil?
        entry[:enum] = serialize_enum(field.enum) unless field.enum.nil?

        unless field.children.empty?
          entry[:children] = build_field_list(field.children)
        end

        entry
      end

      def build_representations
        @registry.representations.map do |name, rep|
          {
            name: name.to_s,
            fields: build_field_list(rep.fields)
          }
        end
      end

      def build_errors
        @registry.errors.map do |_key, err|
          {
            key: err.key.to_s,
            status_code: err.status_code,
            description: err.description
          }
        end
      end

      def serialize_enum(values)
        values.map do |v|
          case v
          when Date, DateTime, Time then v.iso8601
          else v
          end
        end
      end

      def extract_route_map
        map = {}

        @routes.each do |route|
          defaults = route.defaults
          op_name = defaults[:_trane_operation]
          next unless op_name

          path = route.path.spec.to_s.gsub("(.:format)", "")
          method = extract_method(route)

          # Store only the first route per operation: defensive against
          # any host that explicitly declares the same _trane_operation on
          # multiple `match` lines. Rails 8.1.2 collapses `via: [:patch,
          # :put]` into a single route with verb "PATCH|PUT", so this
          # `||=` is a no-op for that case (the verb is canonicalised by
          # `extract_method` to "PATCH").
          map[op_name] ||= { method: method, path: path }
        end

        map
      end

      # NOTE: Trane::RouteValidator guarantees that a route with a contract
      # maps to exactly one HTTP verb, so the `"PATCH|PUT"` (String) and
      # `/^PATCH|PUT$/` (Regexp) multi-verb branches below no longer occur at
      # runtime for contract routes. They are kept as defensive fallbacks.
      def extract_method(route)
        verb = route.verb
        case verb
        when String then verb.split("|").first
        when Regexp then verb.source.scan(/[A-Z]+/).first || verb.source
        else
          if verb.respond_to?(:verb)
            verb.verb.to_s
          else
            verb.to_s
          end
        end
      end
    end
  end
end
