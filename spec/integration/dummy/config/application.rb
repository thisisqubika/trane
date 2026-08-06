# frozen_string_literal: true

require_relative "boot"
require "rails"
require "action_controller/railtie"
require "trane"
require "trane/engine"

module DummyApp
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.api_only = true
    config.hosts.clear
    config.secret_key_base = "test_secret_key_base_for_dummy_app"
  end
end
