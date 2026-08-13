# frozen_string_literal: true

require "trane"

module Trane
  # Test helper for temporarily reconfiguring Trane.
  # Opt-in via: require "trane/testing"
  module Testing
    # Resets Configuration to the given attrs, freezes it, yields, then
    # restores the original state. Guarantees restore even when the block
    # raises.
    #
    # This helper does not touch the route set: `strict_mode` — the only
    # attribute settable via `Trane.configure` — is read when a response is
    # rendered (Trane::Controller::Renderer), never when routes are drawn. The
    # API name is not configurable at all; it is Rails.application.name.
    #
    # `contracts_paths` is also configuration state (set from
    # `config/application.rb` via the internal `_set_contracts_paths!`, not
    # via `Trane.configure`), and `config.reset!` clears it along with
    # `strict_mode`. This helper snapshots and restores both, so a host with a
    # custom `contracts_paths` does not lose it across a call to this helper.
    def self.with_configuration(**attrs)
      raise Trane::Error, "Trane::Testing.with_configuration requires Rails.application" unless defined?(Rails) && Rails.application

      config = Trane.configuration
      snapshot = {
        strict_mode:     config.instance_variable_get(:@strict_mode),
        contracts_paths: config.instance_variable_get(:@contracts_paths),
        frozen:          config.frozen_config?
      }

      config.reset!
      attrs.each { |k, v| config.public_send(:"#{k}=", v) }
      config.freeze!

      yield config
    ensure
      # `config` is nil when the guard above raised; without this check the
      # ensure block would replace that error with a NoMethodError.
      if config
        config.reset!
        config.strict_mode = snapshot[:strict_mode] unless snapshot[:strict_mode].nil?
        # Must run before freeze! below: _set_contracts_paths! raises
        # FrozenError once the config is frozen.
        config._set_contracts_paths!(snapshot[:contracts_paths]) unless snapshot[:contracts_paths].nil?
        config.freeze! if snapshot[:frozen]
      end
    end
  end
end
