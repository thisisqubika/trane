# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trane::Controller do
  it "is a Concern" do
    expect(described_class).to be_a(Module)
  end

  it "includes both Renderer and ErrorHandler when included" do
    captured_rescues = []
    klass = Class.new do
      define_singleton_method(:rescue_from) do |exception_class, options|
        captured_rescues << { exception_class: exception_class, options: options }
      end
    end
    klass.include(described_class)

    expect(captured_rescues).to include(
      exception_class: StandardError,
      options: { with: :_trane_handle_error }
    )

    expect(klass.instance_methods).to include(:render)
  end

  it "exposes Renderer as a submodule" do
    expect(Trane::Controller::Renderer).to be_a(Module)
  end

  it "exposes ErrorHandler as a submodule" do
    expect(Trane::Controller::ErrorHandler).to be_a(Module)
  end
end
