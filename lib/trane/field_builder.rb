# frozen_string_literal: true

module Trane
  class FieldBuilder
    attr_reader :fields

    def initialize
      @fields = []
    end

    # Define a field in the current context.
    #
    # @param name [Symbol] field name
    # @param type [Symbol, nil] field type keyword — mandatory unless `of:` or a block is provided
    # @param extra [Boolean] whether this is an optional extra field
    # @param format [Symbol, nil] format hint (e.g., :iso8601)
    # @param of [Symbol, nil] element type for arrays (infers type: :array)
    # @param enum [Array, nil] set of allowed values; only valid for scalar primitive types
    # @yield optional block for inline nested fields (infers type: :object)
    def field(name, type: nil, extra: false, format: nil, of: nil, enum: nil, &block)
      @fields << _build_field_node(
        name: name, type: type, extra: extra, format: format,
        of: of, enum: enum, child_builder_class: FieldBuilder,
        required: nil, &block
      )
    end

    private

    # Shared field construction logic used by both FieldBuilder and BodyBuilder.
    # Validates presence of at least one type specifier, resolves the type, validates
    # enum constraints, recursively builds children, and returns a FieldNode.
    #
    # @param child_builder_class [Class] builder class to use for nested fields
    # @param required [Boolean, nil] whether the field is required (only meaningful for body fields)
    def _build_field_node(name:, type:, extra:, format:, of:, enum:, child_builder_class:, required:, &block)
      if name.nil? || name.to_s.empty?
        raise ArgumentError, "field name cannot be nil or empty"
      end

      if type.nil? && of.nil? && !block_given?
        raise ArgumentError,
              "field #{name.inspect} must specify type:, of:, or provide a block"
      end

      resolved_type = _resolve_type(type, of, block_given?)
      Trane::Types.validate_enum!(name: name, type: resolved_type, enum: enum) if enum

      children = if block_given?
                   child_builder = child_builder_class.new
                   child_builder.instance_eval(&block)
                   child_builder.fields
                 else
                   []
                 end

      FieldNode.new(
        name: name,
        type: resolved_type,
        extra: extra,
        format: format,
        array_of: of,
        required: required,
        enum: enum,
        children: children
      )
    end

    # Resolve the effective field type from the three type-specifier inputs.
    # Contract: always returns a non-nil Symbol; raises if the precondition in
    # `_build_field_node` is bypassed (i.e. all three inputs falsy).
    def _resolve_type(type, of, has_block)
      return :array if of
      return type if type
      return :object if has_block

      raise ArgumentError,
            "_resolve_type called without type, of, or block — precondition bypassed"
    end
  end
end
