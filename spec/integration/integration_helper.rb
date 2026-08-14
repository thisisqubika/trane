# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rspec"
require "rack/test"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.include Rack::Test::Methods, type: :integration

  config.define_derived_metadata(file_path: %r{spec/integration}) do |metadata|
    metadata[:type] = :integration
  end

  # Re-populate registry and re-apply the dummy initializer before each
  # integration test (unit specs may have reset either between examples).
  config.before(:each, type: :integration) do
    Trane.reset!
    Trane.configure do |c|
      c.strict_mode = :ignore
    end
    Trane::Configuration.instance.freeze!
    Trane::Registry.replace! do |_builder|
      Trane::ContractLoader.each_file(Rails.root, Trane.configuration.contracts_paths) do |file|
        load file
      end
    end
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def app
  DummyApp::Application
end
