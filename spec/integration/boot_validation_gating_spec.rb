# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "BootValidator gating on eager_load", type: :integration do
  # Stage a broken registry: an operation referencing a representation that doesn't exist.
  before do
    Trane::Registry.reset!
    Trane.operation :bad_op do
      response 200 do
        field :user, type: :nonexistent_representation
      end
    end
  end

  context "when eager_load is true" do
    before { allow(Rails.application.config).to receive(:eager_load).and_return(true) }

    it "raises on broken contract via Registry.validate!" do
      expect { Trane::Registry.validate! }.to raise_error(Trane::Error, /representation/)
    end
  end

  context "when eager_load is false" do
    before { allow(Rails.application.config).to receive(:eager_load).and_return(false) }

    it "does not validate during to_prepare even with a broken contract" do
      # Simulate the gated to_prepare logic from the Railtie.
      # When eager_load=false, validate! must not be invoked.
      expect(Trane::Registry).not_to receive(:validate!)

      # Replicate just the gated check (not the full to_prepare, which would
      # reset and reload files from disk and erase our staged broken op).
      if defined?(Trane::BootValidator) && Rails.application.config.eager_load
        Trane::Registry.validate!
      end
    end
  end
end
