# frozen_string_literal: true

module Trane
  class Configuration
    # Default contracts paths resolved relative to the Rails application root.
    # Hosts that need a different location should set
    # `config.trane.contracts_paths` in `config/application.rb`.
    DEFAULT_CONTRACTS_PATHS = [ "app/api_contract" ].freeze

    attr_reader :strict_mode

    # Returns the process-level Configuration instance via the Trane shim.
    # Existing call sites (Trane::Configuration.instance.X) continue to work.
    def self.instance
      Trane.configuration
    end

    def initialize
      @strict_mode     = nil
      @contracts_paths = nil
      @frozen          = false
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

    def strict_mode=(value)
      raise FrozenError, "Trane::Configuration is frozen; cannot modify strict_mode after boot" if @frozen
      @strict_mode = value
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
      @strict_mode     = nil
      @contracts_paths = nil
      @frozen          = false
    end
  end
end
