# frozen_string_literal: true

module Trane
  FieldNode = Data.define(:name, :type, :extra, :format, :array_of, :required, :enum, :children) do
    def initialize(name:, type: nil, extra: false, format: nil, array_of: nil, required: nil, enum: nil, children: [])
      super(
        name: name.to_sym,
        type: type&.to_sym,
        extra: extra,
        format: format&.to_sym,
        array_of: array_of&.to_sym,
        required: required,
        enum: enum&.freeze,
        children: children.freeze
      )
    end
  end
end
