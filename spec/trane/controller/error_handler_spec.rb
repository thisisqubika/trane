# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trane::Controller::ErrorHandler do
  it "is a module that can be included" do
    expect(described_class).to be_a(Module)
  end

  it "calls rescue_from(StandardError, with: :_trane_handle_error) on inclusion" do
    captured = nil
    klass = Class.new do
      define_singleton_method(:rescue_from) do |exception_class, options|
        captured = { exception_class: exception_class, options: options }
      end
    end
    klass.include(described_class)
    expect(captured).to eq(exception_class: StandardError, options: { with: :_trane_handle_error })
  end

  it "does NOT define a render instance method in the module itself" do
    expect(described_class.instance_methods(false)).not_to include(:render)
  end

  it "defines _trane_handle_error as a private method" do
    klass = Class.new do
      def self.rescue_from(*); end
    end
    klass.include(described_class)
    expect(klass.private_instance_methods).to include(:_trane_handle_error)
  end

  it "defines _trane_unhandled_error as a private method" do
    klass = Class.new do
      def self.rescue_from(*); end
    end
    klass.include(described_class)
    expect(klass.private_instance_methods).to include(:_trane_unhandled_error)
  end

  describe "_trane_handle_error lookup" do
    # Each example builds its own anonymous class via `let`, so specs that
    # call `controller_class.define_method(:_trane_unhandled_error)` to
    # override the fallback do not leak the override to other examples.
    subject(:controller) { controller_class.new }

    let(:controller_class) do
      Class.new do
        def self.rescue_from(*); end

        include Trane::Controller::ErrorHandler

        attr_reader :rendered

        def render(options)
          @rendered = options
        end
      end
    end


    it "matches by FQDN when registered as FQDN" do
      stub_const("Outer::Inner::AppError", Class.new(StandardError))
      Trane.errors do
        error "Outer::Inner::AppError", status_code: 409, description: "Conflict"
      end

      controller.send(:_trane_handle_error, Outer::Inner::AppError.new("conflict"))

      expect(controller.rendered[:status]).to eq(409)
      expect(controller.rendered[:json][:errors][0][:key]).to eq("Outer::Inner::AppError")
    end

    it "falls back to short name when FQDN is not registered" do
      stub_const("MyApp::Errors::WidgetNotFound", Class.new(StandardError))
      Trane.errors do
        error :WidgetNotFound, status_code: 404, description: "Widget not found"
      end

      controller.send(:_trane_handle_error, MyApp::Errors::WidgetNotFound.new("missing"))

      expect(controller.rendered[:status]).to eq(404)
      expect(controller.rendered[:json][:errors][0][:key]).to eq("WidgetNotFound")
    end

    it "does not match an unrelated exception by short name against an FQDN registration" do
      stub_const("Errors::UserNotFound", Class.new(StandardError))
      stub_const("SomeGem::UserNotFound", Class.new(StandardError))
      Trane.errors do
        error "Errors::UserNotFound", status_code: 404, description: "User not found"
      end

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      controller.send(:_trane_handle_error, SomeGem::UserNotFound.new("internal gem detail"))

      expect(unhandled_called).to be true
      expect(controller.rendered).to be_nil
    end

    it "calls _trane_unhandled_error when neither FQDN nor short name is registered" do
      stub_const("Totally::Unknown::Error", Class.new(StandardError))

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      controller.send(:_trane_handle_error, Totally::Unknown::Error.new("oops"))

      expect(unhandled_called).to be true
    end

    it "performs lookup without per-exception String#split allocation" do
      stub_const("MyApp::Errors::WidgetNotFound", Class.new(StandardError))
      Trane.errors do
        error "MyApp::Errors::WidgetNotFound", status_code: 404, description: "Widget not found"
      end

      controller.send(:_trane_handle_error, MyApp::Errors::WidgetNotFound.new("warm"))

      GC.disable
      before = GC.stat(:total_allocated_objects)
      100.times { controller.send(:_trane_handle_error, MyApp::Errors::WidgetNotFound.new("x")) }
      after = GC.stat(:total_allocated_objects)
      GC.enable

      per_call = (after - before) / 100.0
      expect(per_call).to be < 10
    end

    it "re-raises a Rails-reserved exception when no Trane match exists" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      exception = ActiveRecord::RecordNotFound.new("raw AR miss")

      begin
        expect {
          controller.send(:_trane_handle_error, exception)
        }.to raise_error(ActiveRecord::RecordNotFound, "raw AR miss")
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end

    it "re-raises a subclass of a Rails-reserved exception when no Trane match exists" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
      stub_const("MyApp::SpecificRecordNotFound", Class.new(ActiveRecord::RecordNotFound))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      exception = MyApp::SpecificRecordNotFound.new("subclass miss")

      begin
        expect {
          controller.send(:_trane_handle_error, exception)
        }.to raise_error(MyApp::SpecificRecordNotFound, "subclass miss")
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end

    it "Trane registry match wins over the Rails-reserved re-raise path" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
      stub_const("UserNotFound", Class.new(ActiveRecord::RecordNotFound))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      Trane.errors do
        error :UserNotFound, status_code: 404, description: "User not found"
      end

      begin
        controller.send(:_trane_handle_error, UserNotFound.new("user gone"))

        expect(controller.rendered[:status]).to eq(404)
        expect(controller.rendered[:json][:errors][0][:key]).to eq("UserNotFound")
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end

    it "routes non-reserved unregistered StandardError to _trane_unhandled_error" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      stub_const("MyApp::WeirdError", Class.new(StandardError))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      begin
        controller.send(:_trane_handle_error, MyApp::WeirdError.new("strange"))

        expect(unhandled_called).to be true
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end

    it "keeps recognizing a Rails-reserved exception after a Zeitwerk-style reload" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      stub_const("MyApp::CustomError", Class.new(StandardError))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "MyApp::CustomError" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      begin
        # First error memoizes the reserved list with the pre-reload class loaded.
        expect {
          controller.send(:_trane_handle_error, MyApp::CustomError.new("before reload"))
        }.to raise_error(MyApp::CustomError, "before reload")

        # Simulate a Zeitwerk reload: same constant name, brand-new Class object.
        reloaded = Class.new(StandardError)
        stub_const("MyApp::CustomError", reloaded)

        expect {
          controller.send(:_trane_handle_error, reloaded.new("after reload"))
        }.to raise_error(reloaded, "after reload")
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end

    describe "_trane_unhandled_error environment gating" do
      def stub_rails_env(local:, production:)
        stub_const("Rails", double("Rails", env: double("env", local?: local, production?: production)))
      end

      it "includes class and message only in local environments (development/test)" do
        stub_rails_env(local: true, production: false)

        controller.send(:_trane_unhandled_error, RuntimeError.new("debug detail"))

        expect(controller.rendered[:json][:errors][0][:message]).to eq("RuntimeError: debug detail")
      end

      it "returns the generic message in production" do
        stub_rails_env(local: false, production: true)

        controller.send(:_trane_unhandled_error, RuntimeError.new("sensitive detail"))

        expect(controller.rendered[:json][:errors][0][:message]).to eq("An unexpected error occurred")
      end

      it "returns the generic message in custom non-local environments (staging/uat)" do
        stub_rails_env(local: false, production: false)

        controller.send(:_trane_unhandled_error, RuntimeError.new("SELECT * FROM users -- sensitive"))

        expect(controller.rendered[:json][:errors][0][:message]).to eq("An unexpected error occurred")
      end
    end

    describe "_trane_unhandled_error reporting" do
      it "reports the exception to Rails.error and logs it before rendering the generic envelope" do
        reports = []
        logs    = []
        error_reporter = double("error_reporter")
        allow(error_reporter).to receive(:report) { |ex, **kw| reports << [ ex, kw ] }
        logger = double("logger")
        allow(logger).to receive(:error) { |msg| logs << msg }

        fake_rails = Module.new
        fake_rails.define_singleton_method(:error)  { error_reporter }
        fake_rails.define_singleton_method(:logger) { logger }
        fake_rails.define_singleton_method(:env)    { Struct.new(:local?, :production?).new(false, true) }
        stub_const("Rails", fake_rails)

        exception = RuntimeError.new("boom during attack probing")
        controller.send(:_trane_unhandled_error, exception)

        expect(reports).to eq([ [ exception, { handled: true, source: "trane" } ] ])
        expect(logs.join).to include("RuntimeError").and include("boom during attack probing")
        expect(controller.rendered[:json][:errors][0][:message]).to eq("An unexpected error occurred")
      end

      it "still renders the envelope when Rails has no error reporter or logger" do
        fake_rails = Module.new
        fake_rails.define_singleton_method(:env) { Struct.new(:local?, :production?).new(false, true) }
        stub_const("Rails", fake_rails)

        expect {
          controller.send(:_trane_unhandled_error, RuntimeError.new("boom"))
        }.not_to raise_error
        expect(controller.rendered[:json][:errors][0][:message]).to eq("An unexpected error occurred")
      end
    end

    it "returns empty reserved list and falls back to unhandled when ActionDispatch is not loaded" do
      described_class.instance_variable_set(:@rails_reserved_names, nil)
      hide_const("ActionDispatch::ExceptionWrapper")

      stub_const("MyApp::SomeError", Class.new(StandardError))

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      begin
        controller.send(:_trane_handle_error, MyApp::SomeError.new("no rails"))

        expect(unhandled_called).to be true
        expect(described_class.rails_reserved_names).to eq(Set.new)
      ensure
        described_class.instance_variable_set(:@rails_reserved_names, nil)
      end
    end
  end
end
