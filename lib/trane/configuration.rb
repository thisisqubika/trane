# frozen_string_literal: true

module Trane
  class Configuration
    # Default contracts paths resolved relative to the Rails application root.
    # Hosts that need a different location should set
    # `config.trane.contracts_paths` in `config/application.rb`.
    DEFAULT_CONTRACTS_PATHS = [ "app/api_contract" ].freeze

    # Valid strict_mode values (nil is also accepted: auto-detect by env).
    STRICT_MODES = %i[raise log ignore].freeze

    # Valid modes for on_missing_operation (what `render contract:` does when
    # the route did not declare `contract: { operation: ... }`).
    ON_MISSING_OPERATION_MODES = %i[raise log fallback].freeze

    # Applied to the serialized response hash immediately before it is encoded,
    # so a host can wrap every success payload in its own envelope. Identity by
    # default: the response is exactly what the contract declares.
    DEFAULT_SUCCESS_ENVELOPE = ->(body) { body }

    # Builds the response body for a rescued exception. Receives the exception
    # and the resolved ErrorDefinition, or nil when no error is registered for
    # it. The status code is NOT the hook's concern: the handler derives it from
    # the definition (or 500), so a host cannot accidentally decouple body and
    # status.
    #
    # The default reproduces the built-in shape, verbosity gating included:
    # exception messages are written for a log audience and can carry SQL,
    # record values or internal hostnames, so only local environments see them.
    DEFAULT_ERROR_ENVELOPE = lambda do |exception, definition|
      if definition
        { errors: [ { key: definition.key.to_s, message: exception.message } ] }
      elsif defined?(Rails) && Rails.env.local?
        { errors: [ { key: "InternalServerError",
                      message: "#{exception.class}: #{exception.message}" } ] }
      else
        { errors: [ { key: "InternalServerError",
                      message: "An unexpected error occurred" } ] }
      end
    end

    attr_reader :strict_mode

    # Returns the process-level Configuration instance via the Trane shim.
    # Existing call sites (Trane::Configuration.instance.X) continue to work.
    def self.instance
      Trane.configuration
    end

    def initialize
      reset!
    end

    # Marks the configuration as frozen. Subsequent setter calls raise
    # FrozenError. Called by the Engine after :load_config_initializers
    # so that runtime code cannot mutate config from another thread or
    # request.
    def freeze!
      @frozen = true
    end

    def frozen_config?
      @frozen
    end

    # Rejects unknown modes at assignment time: an unrecognized value would
    # otherwise fall outside every consumer's case statement and silently
    # disable contract validation (fail-open by typo).
    def strict_mode=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify strict_mode after boot" if @frozen
      unless value.nil? || STRICT_MODES.include?(value)
        raise Trane::Error,
              "strict_mode must be nil (auto-detect) or one of " \
              "#{STRICT_MODES.map(&:inspect).join(', ')} (got #{value.inspect})"
      end
      @strict_mode = value
    end

    # What `render contract:` does when the route did not declare
    # `contract: { operation: ... }` (so no contract can be resolved):
    #
    #   :raise    — fail loud with Trane::Error (default). Without a contract
    #               the field filtering cannot run, and serving the data
    #               unserialized would expose every attribute of the object.
    #   :log      — serve the data unserialized, logging a warning per request.
    #   :fallback — serve the data unserialized, silently.
    def on_missing_operation
      @on_missing_operation || :raise
    end

    def on_missing_operation=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify on_missing_operation after boot" if @frozen
      unless ON_MISSING_OPERATION_MODES.include?(value)
        raise Trane::Error,
              "on_missing_operation must be one of #{ON_MISSING_OPERATION_MODES.map(&:inspect).join(', ')} " \
              "(got #{value.inspect})"
      end
      @on_missing_operation = value
    end

    def success_envelope
      @success_envelope || DEFAULT_SUCCESS_ENVELOPE
    end

    def success_envelope=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify success_envelope after boot" if @frozen
      unless value.respond_to?(:call)
        raise Trane::Error, "success_envelope must respond to #call (got #{value.inspect})"
      end
      @success_envelope = value
    end

    def error_envelope
      @error_envelope || DEFAULT_ERROR_ENVELOPE
    end

    def error_envelope=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify error_envelope after boot" if @frozen
      unless value.respond_to?(:call)
        raise Trane::Error, "error_envelope must respond to #call (got #{value.inspect})"
      end
      @error_envelope = value
    end

    # Whether a Rails-reserved exception (one in
    # ActionDispatch::ExceptionWrapper.rescue_responses) without a registered
    # Trane error is re-raised (false, the default — Rails' own middleware
    # applies its status mapping) or served through the configured error
    # envelope as an unhandled error (true).
    def rescue_rails_reserved
      @rescue_rails_reserved.nil? ? false : @rescue_rails_reserved
    end

    def rescue_rails_reserved=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify rescue_rails_reserved after boot" if @frozen
      unless value == true || value == false
        raise Trane::Error, "rescue_rails_reserved must be true or false (got #{value.inspect})"
      end
      @rescue_rails_reserved = value
    end

    # Returns the effective strict mode for the current environment.
    #
    # @return [Symbol] :raise, :log, or :ignore
    def effective_strict_mode
      return @strict_mode if @strict_mode

      if defined?(Rails)
        case Rails.env.to_s
        when "development", "test" then :raise
        when "production" then :log
        else :log
        end
      else
        :raise
      end
    end

    # Returns the configured contracts paths, falling back to DEFAULT_CONTRACTS_PATHS
    # when none have been explicitly set.
    #
    # To override, set `config.trane.contracts_paths = [...]` in
    # `config/application.rb` — NOT in `config/initializers/trane.rb`, which
    # runs too late for the Engine's `trane.ignore_autoload_paths` initializer.
    def contracts_paths
      @contracts_paths || DEFAULT_CONTRACTS_PATHS
    end

    # Internal — populated by the Engine from app.config.trane.contracts_paths.
    # Host code should use `config.trane.contracts_paths = [...]` in
    # config/application.rb, NOT call this method directly.
    def _set_contracts_paths!(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify contracts_paths after boot" if @frozen
      raise Trane::Error, "contracts_paths must be an Array" unless value.is_a?(Array)
      raise Trane::Error, "contracts_paths must not be empty" if value.empty?
      value.each_with_index do |entry, i|
        raise Trane::Error, "contracts_paths[#{i}] must be a String or Pathname" unless entry.is_a?(String) || entry.is_a?(Pathname)
        str = entry.to_s
        raise Trane::Error, "contracts_paths[#{i}] must not be blank" if str.strip.empty?
        raise Trane::Error, "contracts_paths[#{i}]: glob patterns are not supported" if str.match?(/[*?]/)
      end
      @contracts_paths = value.map(&:to_s)
    end

    def reset!
      @strict_mode           = nil
      @contracts_paths       = nil
      @on_missing_operation  = nil
      @success_envelope      = nil
      @error_envelope        = nil
      @rescue_rails_reserved = nil
      @frozen                = false
    end

    # Internal — full state snapshot/restore for Trane::Testing.
    # Lives here, next to the ivars it enumerates, so adding a new
    # configuration attribute forces updating this list in the same file
    # (instead of silently losing it across a with_configuration block).
    def _dump_state
      {
        strict_mode:           @strict_mode,
        contracts_paths:       @contracts_paths,
        on_missing_operation:  @on_missing_operation,
        success_envelope:      @success_envelope,
        error_envelope:        @error_envelope,
        rescue_rails_reserved: @rescue_rails_reserved,
        frozen:                @frozen
      }
    end

    def _restore_state!(state)
      @strict_mode           = state[:strict_mode]
      @contracts_paths       = state[:contracts_paths]
      @on_missing_operation  = state[:on_missing_operation]
      @success_envelope      = state[:success_envelope]
      @error_envelope        = state[:error_envelope]
      @rescue_rails_reserved = state[:rescue_rails_reserved]
      @frozen                = state[:frozen]
    end
  end
end
