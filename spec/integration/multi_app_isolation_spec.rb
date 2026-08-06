# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Multi-application registry isolation", type: :integration do
  let(:created_apps) { [] }
  let(:app1) { build_isolated_app("app1") }
  let(:app2) { build_isolated_app("app2") }

  after do
    created_apps.each { |app| Trane.uninstall_hooks_for(app) }
  end

  def build_isolated_app(secret_key_suffix)
    klass = Class.new(Rails::Application) do
      config.root = File.expand_path("../dummy", __dir__)
      config.eager_load = false
    end
    klass.config.secret_key_base = "multi_app_isolation_spec_#{secret_key_suffix}"
    Trane.install_hooks_for(klass, Trane::ApplicationHooks.new(
      registry:      Trane::Registry::Instance.new,
      configuration: Trane::Configuration.new
    ))
    created_apps << klass
    klass
  end


  it "Scenario 1: registrations in one app do not leak into another" do
    Trane.with_application(app1) do
      Trane.representation :user_a do
        field :id, type: :integer
      end
      Trane.operation :get_user_a do
        response 200 do
          field :user, type: :user_a
        end
      end
    end

    Trane.with_application(app2) do
      Trane.representation :user_b do
        field :id, type: :integer
      end
      Trane.operation :get_user_b do
        response 200 do
          field :user, type: :user_b
        end
      end
    end

    expect(Trane.hooks_for(app1).registry.operations.keys).to include(:get_user_a)
    expect(Trane.hooks_for(app1).registry.operations.keys).not_to include(:get_user_b)
    expect(Trane.hooks_for(app1).registry.representations.keys).to include(:user_a)
    expect(Trane.hooks_for(app1).registry.representations.keys).not_to include(:user_b)

    expect(Trane.hooks_for(app2).registry.operations.keys).to include(:get_user_b)
    expect(Trane.hooks_for(app2).registry.operations.keys).not_to include(:get_user_a)
    expect(Trane.hooks_for(app2).registry.representations.keys).to include(:user_b)
    expect(Trane.hooks_for(app2).registry.representations.keys).not_to include(:user_a)
  end

  it "Scenario 2: configuration changes in one app do not affect another" do
    Trane.with_application(app1) do
      Trane.configure do |c|
        c.strict_mode = :ignore
      end
    end

    Trane.with_application(app2) do
      Trane.configure do |c|
        c.strict_mode = :log
      end
    end

    expect(Trane.hooks_for(app1).configuration.strict_mode).to eq(:ignore)
    expect(Trane.hooks_for(app2).configuration.strict_mode).to eq(:log)
  end

  it "Scenario 3: reset! in one app does not clear the other" do
    Trane.with_application(app1) do
      Trane.representation(:shared_name) { field :id, type: :integer }
    end

    Trane.with_application(app2) do
      Trane.representation(:shared_name) { field :id, type: :integer }
    end

    Trane.with_application(app1) { Trane.registry.reset! }

    expect(Trane.hooks_for(app1).registry.representations).to be_empty
    expect(Trane.hooks_for(app2).registry.representations.keys).to include(:shared_name)
  end

  it "Scenario 4: the dummy app's registry is unaffected by isolated app activity" do
    dummy_ops_before = Trane.registry.operations.keys

    Trane.with_application(app1) do
      Trane.operation(:isolated_op) { response(200) { } }
    end

    dummy_ops_after = Trane.registry.operations.keys
    expect(dummy_ops_after).to eq(dummy_ops_before)
    expect(dummy_ops_after).not_to include(:isolated_op)
  end
end
