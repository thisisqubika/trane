# frozen_string_literal: true

module Trane
  ErrorDefinition = Data.define(:key, :status_code, :description) do
    def initialize(key:, status_code:, description: nil)
      status_int = status_code.to_i
      unless Trane::Types::HTTP_STATUS_RANGE.cover?(status_int)
        raise ArgumentError,
              "ErrorDefinition #{key.inspect} status_code #{status_code.inspect} is not a valid HTTP status code"
      end
      super(key: key.to_s, status_code: status_int, description: description&.to_s)
    end
  end

  # Builder for `Trane.errors do ... end`
  class ErrorsBuilder
    attr_reader :definitions

    def initialize
      @definitions = []
    end

    # Accepts a Symbol, String (short name or FQDN), or Class.
    # When a Class is given, Class#name is used as the key.
    def error(key, status_code:, description: nil)
      key_str = key.is_a?(Class) ? key.name : key.to_s
      @definitions << ErrorDefinition.new(key: key_str, status_code: status_code, description: description)
    end
  end
end
