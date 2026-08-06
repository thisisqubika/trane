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

    subject(:controller) { controller_class.new }

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
      Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      exception = ActiveRecord::RecordNotFound.new("raw AR miss")

      begin
        expect {
          controller.send(:_trane_handle_error, exception)
        }.to raise_error(ActiveRecord::RecordNotFound, "raw AR miss")
      ensure
        Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      end
    end

    it "re-raises a subclass of a Rails-reserved exception when no Trane match exists" do
      Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
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
        Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      end
    end

    it "Trane registry match wins over the Rails-reserved re-raise path" do
      Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
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
        Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      end
    end

    it "routes non-reserved unregistered StandardError to _trane_unhandled_error" do
      Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      stub_const("MyApp::WeirdError", Class.new(StandardError))
      fake_wrapper = double("ExceptionWrapper", rescue_responses: { "ActiveRecord::RecordNotFound" => :not_found })
      stub_const("ActionDispatch::ExceptionWrapper", fake_wrapper)

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      begin
        controller.send(:_trane_handle_error, MyApp::WeirdError.new("strange"))

        expect(unhandled_called).to be true
      ensure
        Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      end
    end

    it "returns empty reserved list and falls back to unhandled when ActionDispatch is not loaded" do
      Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      hide_const("ActionDispatch::ExceptionWrapper")

      stub_const("MyApp::SomeError", Class.new(StandardError))

      unhandled_called = false
      controller_class.define_method(:_trane_unhandled_error) { |_e| unhandled_called = true }

      begin
        controller.send(:_trane_handle_error, MyApp::SomeError.new("no rails"))

        expect(unhandled_called).to be true
        expect(Trane::Controller::ErrorHandler.rails_reserved_classes).to eq([])
      ensure
        Trane::Controller::ErrorHandler.instance_variable_set(:@rails_reserved_classes, nil)
      end
    end
  end
end
