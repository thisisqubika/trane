# frozen_string_literal: true

RSpec.describe Trane::Configuration do
  subject(:config) { described_class.instance }

  around do |example|
    snapshot = { strict_mode: config.strict_mode }
    example.run
    config.reset!
    config.strict_mode = snapshot[:strict_mode]
  end

  describe "defaults" do
    before { config.reset! }

    it "has nil strict_mode by default" do
      expect(config.strict_mode).to be_nil
    end
  end

  describe "version removal" do
    it "no longer exposes a version reader" do
      expect(config).not_to respond_to(:version)
    end

    it "no longer exposes a version writer" do
      expect(config).not_to respond_to(:version=)
    end
  end

  describe "api_name removal" do
    it "no longer exposes an api_name reader" do
      expect(config).not_to respond_to(:api_name)
    end

    it "no longer exposes an api_name writer" do
      expect(config).not_to respond_to(:api_name=)
    end
  end

  describe "#effective_strict_mode" do
    context "when strict_mode is explicitly set" do
      it "returns the explicit value" do
        config.strict_mode = :ignore
        expect(config.effective_strict_mode).to eq(:ignore)
      end
    end

    context "when strict_mode is nil (auto-detect)" do
      before { config.strict_mode = nil }

      it "defaults to :raise when Rails is not defined" do
        expect(config.effective_strict_mode).to eq(:raise)
      end
    end
  end

  describe "#reset!" do
    it "restores all defaults" do
      config.strict_mode = :ignore

      config.reset!

      expect(config.strict_mode).to be_nil
    end
  end

  describe "Trane.configure" do
    it "yields the configuration instance" do
      Trane.configure do |c|
        c.strict_mode = :log
      end

      expect(config.strict_mode).to eq(:log)
    end
  end

  describe "#strict_mode= validation" do
    before { described_class.instance.reset! }

    it "accepts nil (auto-detect) and the three modes" do
      [ nil, :raise, :log, :ignore ].each do |mode|
        config.strict_mode = mode
        expect(config.strict_mode).to eq(mode)
      end
    end

    it "rejects unknown modes with an actionable error" do
      expect { config.strict_mode = :warn }
        .to raise_error(Trane::Error, /strict_mode must be nil \(auto-detect\) or one of/)
    end

    it "rejects String spellings of valid modes" do
      expect { config.strict_mode = "log" }
        .to raise_error(Trane::Error, /strict_mode must be nil/)
    end
  end

  describe "#on_missing_operation" do
    before { described_class.instance.reset! }

    it "defaults to :raise" do
      expect(config.on_missing_operation).to eq(:raise)
    end

    it "accepts :raise, :log, and :fallback" do
      %i[raise log fallback].each do |mode|
        config.on_missing_operation = mode
        expect(config.on_missing_operation).to eq(mode)
      end
    end

    it "rejects unknown modes with an actionable error" do
      expect { config.on_missing_operation = :silent }
        .to raise_error(Trane::Error, /on_missing_operation must be one of/)
    end

    it "raises FrozenError after freeze!" do
      config.freeze!
      expect { config.on_missing_operation = :log }
        .to raise_error(FrozenError, /Trane::Configuration is frozen/)
    end

    it "reset! restores the :raise default" do
      config.on_missing_operation = :fallback
      config.reset!
      expect(config.on_missing_operation).to eq(:raise)
    end
  end

  describe "#success_envelope" do
    it "defaults to identity" do
      config = described_class.new

      expect(config.success_envelope.call({ a: 1 })).to eq({ a: 1 })
    end

    it "accepts any callable" do
      config = described_class.new
      config.success_envelope = ->(body) { { status: "success" }.merge(body) }

      expect(config.success_envelope.call({ a: 1 })).to eq({ status: "success", a: 1 })
    end

    it "rejects a value that does not respond to #call" do
      config = described_class.new

      expect { config.success_envelope = "nope" }
        .to raise_error(Trane::Error, /must respond to #call/)
    end

    it "rejects assignment after freeze!" do
      config = described_class.new
      config.freeze!

      expect { config.success_envelope = ->(b) { b } }.to raise_error(FrozenError)
    end

    it "survives a with_configuration round trip" do
      config   = described_class.new
      envelope = ->(body) { body }
      config.success_envelope = envelope
      snapshot = config._dump_state
      config.reset!
      config._restore_state!(snapshot)

      expect(config.success_envelope).to be(envelope)
    end
  end

  describe "freeze behavior" do
    before { described_class.instance.reset! }

    it "allows writes before freeze!" do
      expect { described_class.instance.strict_mode = :log }.not_to raise_error
    end

    it "raises FrozenError on strict_mode= after freeze!" do
      described_class.instance.freeze!
      expect { described_class.instance.strict_mode = :raise }
        .to raise_error(FrozenError, /Trane::Configuration is frozen/)
    end

    it "frozen_config? returns true after freeze!" do
      expect(described_class.instance.frozen_config?).to be(false)
      described_class.instance.freeze!
      expect(described_class.instance.frozen_config?).to be(true)
    end

    it "reset! clears the frozen flag and re-enables writes" do
      described_class.instance.freeze!
      described_class.instance.reset!
      expect(described_class.instance.frozen_config?).to be(false)
      expect { described_class.instance.strict_mode = :log }.not_to raise_error
    end
  end
end
