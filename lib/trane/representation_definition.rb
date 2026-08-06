# frozen_string_literal: true

module Trane
  RepresentationDefinition = Data.define(:name, :fields) do
    def initialize(name:, fields: [])
      if name.nil? || name.to_s.empty?
        raise ArgumentError, "RepresentationDefinition name cannot be nil or empty"
      end
      super(name: name.to_sym, fields: fields.freeze)
    end
  end

  # Builder for `Trane.representation :name do ... end`
  class RepresentationBuilder < FieldBuilder
    attr_reader :name

    def initialize(name)
      super()
      @name = name.to_sym
    end

    def build
      RepresentationDefinition.new(name: @name, fields: @fields)
    end
  end
end
