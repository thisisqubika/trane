# frozen_string_literal: true

require_relative "integration_helper"
require "trane/testing"

RSpec.describe "Trane::Testing.with_configuration", type: :integration do
  it "applies configuration and frozen state inside the block" do
    Trane::Testing.with_configuration(strict_mode: :log) do |config|
      expect(config.strict_mode).to eq(:log)
      expect(config.frozen_config?).to be true
    end
  end

  it "yields the configuration object to the block" do
    Trane::Testing.with_configuration(strict_mode: :log) do |config|
      expect(config).to be_a(Trane::Configuration)
    end
  end

  it "restores the original configuration and frozen state on normal exit" do
    original_strict_mode = Trane.configuration.strict_mode
    original_frozen      = Trane.configuration.frozen_config?

    Trane::Testing.with_configuration(strict_mode: :log) {}

    expect(Trane.configuration.strict_mode).to eq(original_strict_mode)
    expect(Trane.configuration.frozen_config?).to eq(original_frozen)
  end

  it "restores the original configuration even when the block raises" do
    original_strict_mode = Trane.configuration.strict_mode
    original_frozen      = Trane.configuration.frozen_config?

    expect {
      Trane::Testing.with_configuration(strict_mode: :log) { raise "boom" }
    }.to raise_error(RuntimeError, "boom")

    expect(Trane.configuration.strict_mode).to eq(original_strict_mode)
    expect(Trane.configuration.frozen_config?).to eq(original_frozen)
  end

  it "does not touch the route set" do
    expect(Rails.application).not_to receive(:reload_routes!)

    Trane::Testing.with_configuration(strict_mode: :log) {}
  end

  it "restores contracts_paths, which reset! also clears" do
    config = Trane.configuration
    config.reset!
    config._set_contracts_paths!(["app/custom_contracts"])
    config.freeze!

    Trane::Testing.with_configuration(strict_mode: :log) {}

    expect(config.contracts_paths).to eq(["app/custom_contracts"])
  end

  it "propagates the missing-Rails.application error without masking it" do
    allow(Rails).to receive(:application).and_return(nil)

    expect { Trane::Testing.with_configuration(strict_mode: :log) {} }
      .to raise_error(Trane::Error, /requires Rails\.application/)
  end
end
