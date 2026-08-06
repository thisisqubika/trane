# frozen_string_literal: true

require "set"
require "date"

module Trane
  module Types
    PRIMITIVES = Set[
      :string, :integer, :float, :boolean,
      :date, :datetime, :object, :array
    ].freeze

    # Types that support enum: (scalar primitives only)
    ENUMERABLE_TYPES = Set[
      :string, :integer, :float, :boolean, :date, :datetime
    ].freeze

    HTTP_STATUS_RANGE = (100..599).freeze

    def self.primitive?(type)
      type.nil? || PRIMITIVES.include?(type)
    end

    def self.representation_reference?(type)
      !type.nil? && !PRIMITIVES.include?(type)
    end

    # Strict type-match: each value must be EXACTLY of the declared type's class.
    # No coercion (Integer not accepted for :float, DateTime not accepted for :date, etc).
    def self.value_matches_type?(value, type)
      case type
      when :string   then value.is_a?(String)
      when :integer  then value.is_a?(Integer)
      when :float    then value.is_a?(Float)
      when :boolean  then value.is_a?(TrueClass) || value.is_a?(FalseClass)
      when :date     then value.is_a?(Date) && !value.is_a?(DateTime)
      when :datetime then value.is_a?(DateTime) || value.is_a?(Time) ||
                          (defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone))
      else false
      end
    end

    # Validates the structure and content of an enum: declaration. Raises ArgumentError if invalid.
    def self.validate_enum!(name:, type:, enum:)
      return if enum.nil?

      unless enum.is_a?(Array)
        raise ArgumentError, "field/param :#{name} enum: must be an Array (got #{enum.class})"
      end

      if enum.empty?
        raise ArgumentError, "field/param :#{name} enum: must be a non-empty Array"
      end

      unless ENUMERABLE_TYPES.include?(type)
        raise ArgumentError,
              "field/param :#{name} enum: is only supported for scalar primitive types " \
              "(#{ENUMERABLE_TYPES.to_a.map { |t| ":#{t}" }.join(', ')}). Got :#{type}."
      end

      enum.each do |value|
        unless value_matches_type?(value, type)
          raise ArgumentError,
                "field/param :#{name} enum value #{value.inspect} (#{value.class}) is not coherent with type :#{type}"
        end
      end
    end
  end
end
