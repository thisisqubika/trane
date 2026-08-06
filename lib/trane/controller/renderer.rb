# frozen_string_literal: true

require "active_support/concern"
require "json"

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
            # Debug fallback: when the route did not inject _trane_operation,
            # we cannot resolve a ResponseDefinition, so we cannot run the
            # serializer or the as_json-skip optimization. Correctness > perf.
            return super(json: contract_data, status: status, **extra_options, &block)
          end

          hooks    = Trane.current_hooks
          registry = hooks.registry

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
          strict      = hooks.configuration.effective_strict_mode
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
    end
  end
end
