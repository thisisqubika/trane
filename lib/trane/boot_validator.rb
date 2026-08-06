# frozen_string_literal: true

module Trane
  class BootValidator
    # Validate referential integrity of the registry.
    # Ensures that all representation references in operations exist,
    # and all error keys referenced by operations are registered.
    # Consumes the precomputed errors_by_name index from the snapshot.
    #
    # @param registry [Module] Trane::Registry
    # @raise [Trane::Error] if any references are invalid
    def self.validate!(registry)
      errors         = []
      errors_by_name = registry.errors_by_name

      registry.operations.each do |op_name, op|
        op.responses.each do |status, resp|
          resp.fields.each do |field|
            errors.concat(validate_field_references(field, registry, context: "operation :#{op_name} response #{status}"))
          end
        end

        op.error_keys.each do |key|
          key_str = key.to_s
          next if errors_by_name.key?(key_str)

          errors << "operation :#{op_name} references error :#{key}, but no such error is registered"
        end
      end

      return if errors.empty?

      raise Trane::Error, "Trane boot validation failed:\n  #{errors.join("\n  ")}"
    end

    class << self
      private

      def validate_field_references(field, registry, context:, path: [])
        errors = []
        joined_path = (path + [ field.name ]).join(".")

        if field.type && Types.representation_reference?(field.type)
          unless registry.representations.key?(field.type)
            errors << "#{context}: field :#{joined_path} references representation :#{field.type}, which does not exist"
          end
        end

        if field.array_of && Types.representation_reference?(field.array_of)
          unless registry.representations.key?(field.array_of)
            errors << "#{context}: field :#{joined_path} has array of :#{field.array_of}, which does not exist as a representation"
          end
        end

        child_path = path + [ field.name ]
        field.children.each do |child|
          errors.concat(validate_field_references(child, registry, context: context, path: child_path))
        end

        errors
      end
    end
  end
end
