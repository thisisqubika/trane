# frozen_string_literal: true

module Trane
  ParamDefinition = Data.define(:name, :type, :required, :location, :enum) do
    # Build a frozen param definition for an operation request schema.
    #
    # @param name [Symbol, String] coerced to Symbol
    # @param type [Symbol, String] coerced to Symbol
    # @param location [Symbol, String] one of +:path+, +:query+; coerced to Symbol
    # @param required [Boolean] whether the param must be present in the request.
    #   Defaults to +false+. DSL callers override per location: +path+ always
    #   passes +true+; +query+ honours the caller's +required:+ keyword (also
    #   defaulting to +false+).
    # @param enum [Array, nil] frozen on assignment
    def initialize(name:, type:, location:, required: false, enum: nil)
      super(
        name: name.to_sym,
        type: type.to_sym,
        required: required,
        location: location.to_sym,
        enum: enum&.freeze
      )
    end
  end
end
