# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trane::Controller::Renderer do
  it "is a module that can be included" do
    expect(described_class).to be_a(Module)
  end

  it "does NOT install rescue_from on inclusion" do
    klass = Class.new do
      def self.rescue_from(*); raise "should not be called"; end
    end
    expect { klass.include(described_class) }.not_to raise_error
  end

  it "defines a render instance method" do
    klass = Class.new { include Trane::Controller::Renderer }
    expect(klass.instance_methods).to include(:render)
  end

  it "does NOT define _trane_handle_error" do
    klass = Class.new { include Trane::Controller::Renderer }
    expect(klass.instance_methods).not_to include(:_trane_handle_error)
  end

  it "does NOT define _trane_unhandled_error" do
    klass = Class.new { include Trane::Controller::Renderer }
    expect(klass.instance_methods).not_to include(:_trane_unhandled_error)
  end

  it "delegates to super for non-contract options hash" do
    klass = Class.new do
      def render(options = nil, _extra = {}, &_blk)
        [ :super_called, options ]
      end
      include Trane::Controller::Renderer
    end
    expect(klass.new.render(plain: "hi")).to eq([ :super_called, { plain: "hi" } ])
  end

  it "raises ArgumentError when :callback (JSONP) is passed via extra_options" do
    parent = Class.new do
      def render(_options = nil, _extra = {}, &_blk); end
    end
    klass = Class.new(parent) do
      def request; Struct.new(:path_parameters).new({ _trane_operation: :op }); end
      def params; {}; end
      include Trane::Controller::Renderer
    end
    expect {
      klass.new.render({ contract: {} }, { callback: "cb" })
    }.to raise_error(ArgumentError, /JSONP/)
  end

  it "does not mutate the caller's options hash" do
    Trane.configure { |c| c.on_missing_operation = :fallback }
    parent = Class.new do
      def render(_options = nil, _extra = {}, &_blk); end
    end
    klass = Class.new(parent) do
      def request; Struct.new(:path_parameters).new({ _trane_operation: nil }); end
      def params; {}; end
      include Trane::Controller::Renderer
    end

    options = { contract: { user: { id: 1 } }, status: :created }
    klass.new.render(options)

    expect(options).to have_key(:contract)
    expect(options).to have_key(:status)
  end

  describe "missing route contract (on_missing_operation)" do
    def build_controller
      parent = Class.new do
        attr_reader :super_options
        def render(options = nil, _extra = {}, &_blk)
          @super_options = options
        end
      end
      Class.new(parent) do
        def request; Struct.new(:path_parameters).new({ _trane_operation: nil }); end
        def params; {}; end
        include Trane::Controller::Renderer
      end.new
    end

    it "raises by default instead of serving unserialized data" do
      controller = build_controller

      expect {
        controller.render(contract: { user: { id: 1, password_digest: "secret" } })
      }.to raise_error(Trane::Error, /did not declare a contract/)
      expect(controller.super_options).to be_nil
    end

    it "logs a warning and serves unserialized data in :log mode" do
      Trane.configure { |c| c.on_missing_operation = :log }
      require "logger"
      warnings = []
      logger   = instance_double(Logger)
      allow(logger).to receive(:warn) { |msg| warnings << msg }
      fake_rails = Module.new
      fake_rails.define_singleton_method(:logger) { logger }
      stub_const("Rails", fake_rails)
      controller = build_controller

      controller.render(contract: { user: { id: 1 } }, status: :ok)

      expect(warnings.join).to match(/\[Trane\].*without contract metadata/)
      expect(controller.super_options).to eq(json: { user: { id: 1 } }, status: :ok)
    end

    it "serves unserialized data silently in :fallback mode" do
      Trane.configure { |c| c.on_missing_operation = :fallback }
      controller = build_controller

      expect {
        controller.render(contract: { user: { id: 1 } }, status: :ok)
      }.not_to output.to_stderr

      expect(controller.super_options).to eq(json: { user: { id: 1 } }, status: :ok)
    end
  end
end
