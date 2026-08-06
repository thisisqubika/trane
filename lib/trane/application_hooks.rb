# frozen_string_literal: true

module Trane
  # Container attached to Rails.application.config.trane holding the
  # per-application Trane registry and configuration.
  class ApplicationHooks
    attr_reader :registry, :configuration

    def initialize(registry:, configuration:)
      @registry = registry
      @configuration = configuration
    end
  end
end
