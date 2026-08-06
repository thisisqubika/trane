# frozen_string_literal: true

RSpec.describe Trane::Configuration, "#contracts_paths" do
  subject(:config) { described_class.new }

  describe "#contracts_paths (default)" do
    it "returns DEFAULT_CONTRACTS_PATHS when never set" do
      expect(config.contracts_paths).to eq(Trane::Configuration::DEFAULT_CONTRACTS_PATHS)
    end

    it "returns a frozen array" do
      expect(Trane::Configuration::DEFAULT_CONTRACTS_PATHS).to be_frozen
    end
  end

  describe "#_set_contracts_paths!" do
    it "accepts an array of strings and stores them" do
      config._set_contracts_paths!([ "a", "b" ])
      expect(config.contracts_paths).to eq([ "a", "b" ])
    end

    it "accepts Pathname entries and converts to strings" do
      config._set_contracts_paths!([ Pathname.new("app/contracts") ])
      expect(config.contracts_paths).to eq([ "app/contracts" ])
    end

    it "accepts a mix of string and Pathname entries" do
      config._set_contracts_paths!([ "a", Pathname.new("b") ])
      expect(config.contracts_paths).to eq([ "a", "b" ])
    end

    it "makes the reader return the given paths" do
      config._set_contracts_paths!([ "custom/path" ])
      expect(config.contracts_paths).to eq([ "custom/path" ])
    end

    context "validation errors" do
      it "raises Trane::Error when value is nil" do
        expect { config._set_contracts_paths!(nil) }
          .to raise_error(Trane::Error, /must be an Array/)
      end

      it "raises Trane::Error when value is not an Array" do
        expect { config._set_contracts_paths!("app/contracts") }
          .to raise_error(Trane::Error, /must be an Array/)
      end

      it "raises Trane::Error when value is an empty Array" do
        expect { config._set_contracts_paths!([]) }
          .to raise_error(Trane::Error, /must not be empty/)
      end

      it "raises Trane::Error when an entry is neither String nor Pathname" do
        expect { config._set_contracts_paths!([ 42 ]) }
          .to raise_error(Trane::Error, /must be a String or Pathname/)
      end

      it "raises Trane::Error when an entry is a blank string" do
        expect { config._set_contracts_paths!([ "   " ]) }
          .to raise_error(Trane::Error, /must not be blank/)
      end

      it "raises Trane::Error when an entry contains a glob wildcard *" do
        expect { config._set_contracts_paths!([ "app/*" ]) }
          .to raise_error(Trane::Error, /glob patterns are not supported/)
      end

      it "raises Trane::Error when an entry contains a glob wildcard ?" do
        expect { config._set_contracts_paths!([ "app/?" ]) }
          .to raise_error(Trane::Error, /glob patterns are not supported/)
      end
    end

    context "after freeze!" do
      before { config.freeze! }

      it "raises FrozenError" do
        expect { config._set_contracts_paths!([ "x" ]) }
          .to raise_error(FrozenError, /Trane::Configuration is frozen/)
      end
    end
  end

  describe "#reset!" do
    it "clears a previously set contracts_paths, restoring the default" do
      config._set_contracts_paths!([ "custom" ])
      config.reset!
      expect(config.contracts_paths).to eq(Trane::Configuration::DEFAULT_CONTRACTS_PATHS)
    end

    it "clears the frozen flag, allowing writes again" do
      config._set_contracts_paths!([ "custom" ])
      config.freeze!
      config.reset!
      expect { config._set_contracts_paths!([ "other" ]) }.not_to raise_error
    end
  end
end
