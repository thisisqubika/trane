# frozen_string_literal: true

module Trane
  class Serializer
    # @param response_definition [ResponseDefinition]
    # @param registry [Module] Trane::Registry
    # @param strict_mode [Symbol] :raise, :log, or :ignore
    # Instances are frozen post-init; share freely across threads.
    def initialize(response_definition, registry, strict_mode: :ignore)
      @response_definition = response_definition
      @registry            = registry
      @strict_mode         = strict_mode
      freeze
    end

    # Serialize data according to the response definition.
    #
    # @param data [Hash, Object] the data to serialize (hash of root-level keys)
    # @param extra_attributes [Set<String>] dot-notation paths of extra fields to include
    # @return [Hash] serialized result
    def serialize(data, extra_attributes: ExtraAttributesFilter::EMPTY)
      result = serialize_fields(@response_definition.fields, data, extra_attributes: extra_attributes, prefix: "")

      if @strict_mode != :ignore
        ContractValidator.validate_response!(
          @response_definition, result, @registry, mode: @strict_mode
        )
      end

      result
    end

    private

    # Serialize a list of fields against a data source.
    #
    # @param fields [Array<FieldNode>] field definitions
    # @param data [Hash, Object] the data to extract values from
    # @param extra_attributes [Set<String>] extra attribute paths
    # @param prefix [String] current dot-notation prefix
    # @return [Hash]
    def serialize_fields(fields, data, extra_attributes:, prefix:)
      result = {}

      fields.each do |field|
        if field.extra
          path = build_path(prefix, field.name)
          next unless extra_attributes.include?(path)
        end

        value = extract_value(data, field.name)
        result[field.name] = serialize_value(field, value, extra_attributes: extra_attributes, prefix: prefix)
      end

      result
    end

    # Serialize a single field value.
    def serialize_value(field, value, extra_attributes:, prefix:)
      return nil if value.nil?

      if field.type == :array
        return serialize_array(field, value, extra_attributes: extra_attributes, prefix: prefix)
      end

      unless field.children.empty?
        new_prefix = build_path(prefix, field.name)
        return serialize_fields(field.children, value, extra_attributes: extra_attributes, prefix: new_prefix)
      end

      rep = @registry.representations[field.type]
      if rep
        new_prefix = build_path(prefix, field.name)
        return serialize_fields(rep.fields, value, extra_attributes: extra_attributes, prefix: new_prefix)
      end

      if field.format == :iso8601 && value.respond_to?(:iso8601)
        return value.iso8601
      end

      value
    end

    # Serialize an array field.
    def serialize_array(field, value, extra_attributes:, prefix:)
      unless array_like?(value)
        handle_non_iterable_array(value, build_path(prefix, field.name))
        return []
      end

      if field.array_of || !field.children.empty?
        element_prefix = build_path(prefix, field.name)
        value.map do |element|
          if field.array_of
            rep = @registry.representations[field.array_of]
            rep ? serialize_fields(rep.fields, element, extra_attributes: extra_attributes, prefix: element_prefix) : element
          else
            serialize_fields(field.children, element, extra_attributes: extra_attributes, prefix: element_prefix)
          end
        end
      else
        # Fresh Array in both branches: never alias the caller's collection
        # into the result, and normalize non-Array Enumerables (Set, lazy
        # enumerators) into something JSON.generate can serialize. dup/to_a
        # instead of an identity map: same semantics without dispatching a
        # block per element (memcpy vs O(n) yields on large scalar arrays).
        value.is_a?(Array) ? value.dup : value.to_a
      end
    end

    def array_like?(value)
      value.is_a?(Array) || (value.is_a?(Enumerable) && !value.is_a?(Hash))
    end

    def handle_non_iterable_array(value, path)
      return if @strict_mode == :ignore

      message = "Trane: expected Array at #{path}, got #{value.class}"
      case @strict_mode
      when :raise
        raise ContractViolation, message
      when :log
        Trane.log_warning(message)
      end
    end

    # Lazily compose dot-notation path; allocates only when a consumer
    # (extras gate, nested-rep recursion, or strict-mode violation) needs it.
    def build_path(prefix, leaf_sym)
      prefix.empty? ? leaf_sym.name : "#{prefix}.#{leaf_sym}"
    end

    # Extract a value from data (supports both Hash and objects).
    #
    # For objects, only fields the receiver explicitly responds to are
    # extracted; anything else returns nil. NoMethodError raised inside a
    # getter is left to propagate so genuine bugs aren't swallowed.
    def extract_value(data, field_name)
      if data.is_a?(Hash)
        return data[field_name] if data.key?(field_name)
        data[field_name.name]
      elsif data.respond_to?(field_name)
        data.public_send(field_name)
      end
    end
  end
end
