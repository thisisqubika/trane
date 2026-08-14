# frozen_string_literal: true

require "active_support/concern"
require "json"
require "rack/utils"

module Trane
  module Controller
    # Mixin that adds `render contract: data` support to a controller.
    # Include in your API base controller (e.g. Api::BaseController <
    # ActionController::API). Does NOT install any rescue_from handlers —
    # combine with Trane::Controller::ErrorHandler or use the composer
    # Trane::Controller for both.
    #
    # Caveat: if the including class also `prepend`s a custom `#render`,
    # the prepended one runs first; chain via `super` to reach this one.
    module Renderer
      extend ActiveSupport::Concern

      def render(options = nil, extra_options = {}, &block)
        if options.is_a?(Hash) && options.key?(:contract)
          if extra_options.is_a?(Hash) && extra_options.key?(:callback)
            raise ArgumentError,
                  "Trane: render contract: does not support :callback (JSONP). " \
                  "Use render json: directly if JSONP is required."
          end

          contract_data = options[:contract]
          status        = options[:status] || :ok
          status_int    = ::Rack::Utils.status_code(status)

          op_name = _trane_operation_name
          unless op_name
            # The route did not inject _trane_operation, so no contract can
            # be resolved and the field filtering cannot run. Serving the
            # data unserialized would expose every attribute of the object
            # (fail-open on the gem's only field filter), so the default is
            # to fail loud, consistent with the unknown-operation and
            # missing-response paths below. Hosts opt into the old behavior
            # via config.on_missing_operation = :log / :fallback.
            case Trane.configuration.on_missing_operation
            when :fallback
              return super(json: contract_data, status: status, **extra_options, &block)
            when :log
              _trane_log_missing_operation
              return super(json: contract_data, status: status, **extra_options, &block)
            else
              raise Trane::Error,
                    "Trane: render contract: was called but the route did not declare a contract, " \
                    "so the response cannot be serialized or filtered. " \
                    "Add `contract: { operation: :<operation_name> }` to this route in routes.rb, " \
                    "or set `config.on_missing_operation` to :log or :fallback to serve the data unserialized."
            end
          end

          registry = Trane.registry

          op = registry.operations[op_name]
          unless op
            raise Trane::Error,
                  "Trane: no operation registered for '#{op_name}'. " \
                  "Define it with Trane.operation(:#{op_name}) { ... }"
          end

          response_def = op.responses[status_int]
          unless response_def
            raise Trane::Error,
                  "Trane: operation '#{op_name}' has no response defined for status #{status_int}."
          end

          extra_attrs = ExtraAttributesFilter.parse(params)
          strict      = Trane.configuration.effective_strict_mode
          serializer  = registry.compiled_serializer_for(response_def, strict)
          hash        = serializer.serialize(contract_data, extra_attributes: extra_attrs)

          body = ::JSON.generate(hash)
          super(
            plain: body,
            status: status,
            content_type: extra_options.fetch(:content_type, "application/json; charset=utf-8"),
            **extra_options.except(:content_type),
            &block
          )
        else
          super
        end
      end

      private

      def _trane_operation_name
        op = request.path_parameters[:_trane_operation]
        op&.to_sym
      end

      def _trane_log_missing_operation
        Trane.log_warning(
          "[Trane] render contract: called on a route without contract metadata; " \
          "serving unserialized JSON. Add `contract: { operation: ... }` to the route in routes.rb."
        )
      end
    end
  end
end
