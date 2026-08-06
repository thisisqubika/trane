# frozen_string_literal: true

require_relative "integration_helper"
require "tmpdir"
require "pathname"

RSpec.describe "Trane::Engine trane.ignore_autoload_paths initializer", type: :integration do
  let(:initializer) do
    Trane::Engine.initializers.find { |i| i.name == "trane.ignore_autoload_paths" }
  end
  let(:install_initializer) do
    Trane::Engine.initializers.find { |i| i.name == "trane.install_application_hooks" }
  end

  def run_initializer(app)
    initializer.instance_exec(app, &initializer.block)
  end

  def with_unfrozen_config
    original_paths  = Trane.configuration.instance_variable_get(:@contracts_paths)
    original_frozen = Trane.configuration.instance_variable_get(:@frozen)
    Trane.configuration.instance_variable_set(:@frozen, false)
    Trane.configuration.instance_variable_set(:@contracts_paths, nil)
    yield
  ensure
    Trane.configuration.instance_variable_set(:@frozen, false)
    Trane.configuration.instance_variable_set(:@contracts_paths, original_paths)
    Trane.configuration.instance_variable_set(:@frozen, original_frozen)
  end


  it "calls ignore on both autoloaders with the realpath string" do
    Dir.mktmpdir do |tmpdir|
      subdir = File.join(tmpdir, "custom")
      FileUtils.mkdir_p(subdir)

      main_autoloader = double("main_autoloader", ignore: nil)
      once_autoloader = double("once_autoloader", ignore: nil)
      trane_opts      = double("trane_opts", respond_to?: true, contracts_paths: [ "custom" ])
      app_config      = double("app_config",  respond_to?: true, trane: trane_opts)
      app             = double("app", root: Pathname.new(tmpdir), config: app_config)

      allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
      allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)

      expected_realpath = Pathname.new(subdir).realpath.to_s

      expect(main_autoloader).to receive(:ignore).with(expected_realpath)
      expect(once_autoloader).to receive(:ignore).with(expected_realpath)

      with_unfrozen_config do
        run_initializer(app)
        expect(Trane.configuration.contracts_paths).to eq([ "custom" ])
      end
    end
  end

  it "skips a path that does not exist (no ignore call)" do
    Dir.mktmpdir do |tmpdir|
      main_autoloader = double("main_autoloader")
      once_autoloader = double("once_autoloader")
      trane_opts      = double("trane_opts", respond_to?: true, contracts_paths: [ "nonexistent" ])
      app_config      = double("app_config",  respond_to?: true, trane: trane_opts)
      app             = double("app", root: Pathname.new(tmpdir), config: app_config)

      allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
      allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)

      expect(main_autoloader).not_to receive(:ignore)
      expect(once_autoloader).not_to receive(:ignore)

      with_unfrozen_config do
        expect { run_initializer(app) }.not_to raise_error
      end
    end
  end

  it "skips a broken symlink path (no ignore call)" do
    Dir.mktmpdir do |tmpdir|
      symlink_path = File.join(tmpdir, "broken_link")
      File.symlink(File.join(tmpdir, "nonexistent_target"), symlink_path)

      main_autoloader = double("main_autoloader")
      once_autoloader = double("once_autoloader")
      trane_opts      = double("trane_opts", respond_to?: true, contracts_paths: [ "broken_link" ])
      app_config      = double("app_config",  respond_to?: true, trane: trane_opts)
      app             = double("app", root: Pathname.new(tmpdir), config: app_config)

      allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
      allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)

      expect(main_autoloader).not_to receive(:ignore)
      expect(once_autoloader).not_to receive(:ignore)

      with_unfrozen_config do
        expect { run_initializer(app) }.not_to raise_error
      end
    end
  end

  it "mirrors contracts_paths into Trane::Configuration" do
    Dir.mktmpdir do |tmpdir|
      subdir = File.join(tmpdir, "my_contracts")
      FileUtils.mkdir_p(subdir)

      main_autoloader = double("main_autoloader", ignore: nil)
      once_autoloader = double("once_autoloader", ignore: nil)
      trane_opts      = double("trane_opts", respond_to?: true, contracts_paths: [ "my_contracts" ])
      app_config      = double("app_config",  respond_to?: true, trane: trane_opts)
      app             = double("app", root: Pathname.new(tmpdir), config: app_config)

      allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
      allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)

      with_unfrozen_config do
        run_initializer(app)
        expect(Trane.configuration.contracts_paths).to eq([ "my_contracts" ])
      end
    end
  end


  def run_install_initializer(app)
    install_initializer.instance_exec(app, &install_initializer.block)
  end

  def build_fresh_app(suffix)
    klass = Class.new(Rails::Application) do
      config.root = File.expand_path("../dummy", __dir__)
      config.eager_load = false
    end
    klass.config.secret_key_base = "ignore_paths_regression_#{suffix}"
    klass
  end

  it "does not emit a [Trane] fallback warning when running ignore_autoload_paths after install_application_hooks" do
    app = build_fresh_app("no_warn")

    begin
      run_install_initializer(app)

      warnings = []
      allow(Rails.logger).to receive(:warn) { |msg| warnings << msg }
      allow_any_instance_of(Object).to receive(:warn) { |_, msg| warnings << msg }

      Dir.mktmpdir do |tmpdir|
        main_autoloader = double("main_autoloader", ignore: nil)
        once_autoloader = double("once_autoloader", ignore: nil)
        trane_opts      = double("trane_opts", respond_to?: true,
                                 contracts_paths: Trane::Configuration::DEFAULT_CONTRACTS_PATHS)
        app_config      = double("app_config", respond_to?: true, trane: trane_opts)
        fake_app        = double("fake_app", root: Pathname.new(tmpdir), config: app_config)

        allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
        allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)
        allow(Rails).to receive(:application).and_return(app)

        run_initializer(fake_app)
      end

      trane_warnings = warnings.grep(/\[Trane\] current_hooks falling back/)
      expect(trane_warnings).to be_empty
    ensure
      Trane.uninstall_hooks_for(app)
    end
  end

  it "does not raise FrozenError when a second app runs ignore_autoload_paths after its own install_application_hooks" do
    app1 = build_fresh_app("frozen_app1")
    app2 = build_fresh_app("frozen_app2")

    begin
      run_install_initializer(app1)
      Trane.hooks_for(app1).configuration.freeze!

      run_install_initializer(app2)

      Dir.mktmpdir do |tmpdir|
        main_autoloader = double("main_autoloader", ignore: nil)
        once_autoloader = double("once_autoloader", ignore: nil)
        trane_opts      = double("trane_opts", respond_to?: true,
                                 contracts_paths: Trane::Configuration::DEFAULT_CONTRACTS_PATHS)
        app_config      = double("app_config", respond_to?: true, trane: trane_opts)
        fake_app        = double("fake_app", root: Pathname.new(tmpdir), config: app_config)

        allow(Rails).to receive_message_chain(:autoloaders, :main).and_return(main_autoloader)
        allow(Rails).to receive_message_chain(:autoloaders, :once).and_return(once_autoloader)
        allow(Rails).to receive(:application).and_return(app2)

        expect { run_initializer(fake_app) }.not_to raise_error
      end
    ensure
      Trane.uninstall_hooks_for(app1)
      Trane.uninstall_hooks_for(app2)
    end
  end
end
