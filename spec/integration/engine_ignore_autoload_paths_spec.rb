# frozen_string_literal: true

require_relative "integration_helper"
require "tmpdir"
require "pathname"

RSpec.describe "Trane::Engine trane.ignore_autoload_paths initializer", type: :integration do
  let(:initializer) do
    Trane::Engine.initializers.find { |i| i.name == "trane.ignore_autoload_paths" }
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
end
