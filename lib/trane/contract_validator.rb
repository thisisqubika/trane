# frozen_string_literal: true

module Trane
  class ContractViolation < Trane::Error; end

  class ContractValidator
    # Validate that a serialized result conforms to the response definition.
    #
    # @param response_def [ResponseDefinition]
    # @param result [Hash] the serialized output
    # @param registry [Module] Trane::Registry
    # @param mode [Symbol] :raise or :log
    def self.validate_response!(response_def, result, registry, mode:)
      violations = collect_violations(response_def.fields, result, registry, prefix: "")
      return if violations.empty?

      message = "Trane contract violations (status #{response_def.status}):\n  #{violations.join("\n  ")}"
      case mode
      when :raise
        raise ContractViolation, message
      when :log
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn(message)
        else
          warn(message)
        end
      end
    end

    class << self
      private

      def collect_violations(fields, result, registry, prefix:)
        violations = []

        declared_keys = registry.validator_declared_field_names_for(fields)

        # Check for missing declared (non-extra) keys
        declared_keys.each do |key|
          unless result.key?(key)
            violations << "#{format_path(prefix, key)}: missing from response"
          end
        end

        # Check for undeclared keys
        allowed_keys = registry.validator_field_names_for(fields)
        result.each_key do |key|
          unless allowed_keys.include?(key)
            violations << "#{format_path(prefix, key)}: undeclared field in response"
          end
        end

        # Recurse into representation fields; flag composite values that
        # landed in scalar leaves
        fields.each do |field|
          value = result[field.name]
          next if value.nil?

          rep = registry.representations[field.type] if field.type
          if rep && value.is_a?(Hash)
            child_prefix = format_path(prefix, field.name)
            violations.concat(collect_violations(rep.fields, value, registry, prefix: child_prefix))
          elsif composite_scalar_violation?(field, value)
            violations << "#{format_path(prefix, field.name)}: composite #{value.class} value " \
                          "in scalar field (declared type :#{field.type})"
          end
        end

        violations
      end

      # A Hash or Array in a field declared as a scalar leaf means the
      # caller passed a composite object where a value was expected — the
      # serializer emits leaf values verbatim, so the whole object (every
      # attribute, e.g. a full model as_json) would reach the client.
      # Only scalar leaf types are checked: :object is free-form by
      # declaration, :array carries Arrays, representation-typed fields
      # recurse above, and fields with children are structurally filtered
      # by the serializer.
      def composite_scalar_violation?(field, value)
        return false unless Types::ENUMERABLE_TYPES.include?(field.type)
        return false unless field.children.nil? || field.children.empty?

        value.is_a?(Hash) || value.is_a?(Array)
      end

      def format_path(prefix, key)
        prefix.empty? ? key.to_s : "#{prefix}.#{key}"
      end
    end
  end
end
