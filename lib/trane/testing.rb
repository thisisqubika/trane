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
    # This helper does not touch the route set: none of the attributes
    # settable via `Trane.configure` (`strict_mode`, `on_missing_operation`,
    # `success_envelope`, `error_envelope`, `rescue_rails_reserved`) are read
    # at route-draw time — `strict_mode`, for instance, is read when a
    # response is rendered (Trane::Controller::Renderer). The API name is not
    # configurable at all; it is Rails.application.name.
    #
    # `contracts_paths` is also configuration state (set from
    # `config/application.rb` via the internal `_set_contracts_paths!`, not
    # via `Trane.configure`), and `config.reset!` clears it along with
    # `strict_mode`. This helper snapshots and restores both, so a host with a
    # custom `contracts_paths` does not lose it across a call to this helper.
    def self.with_configuration(**attrs)
      raise Trane::Error, "Trane::Testing.with_configuration requires Rails.application" unless defined?(Rails) && Rails.application

      config = Trane.configuration
      snapshot = config._dump_state

      config.reset!
      attrs.each { |k, v| config.public_send(:"#{k}=", v) }
      config.freeze!

      yield config
    ensure
      # `config` is nil when the guard above raised; without this check the
      # ensure block would replace that error with a NoMethodError.
      config._restore_state!(snapshot) if config
    end
  end
end
