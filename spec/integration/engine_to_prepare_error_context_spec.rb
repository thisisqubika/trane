# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Engine to_prepare error context", type: :integration do
  let(:dummy_contract_dir) do
    Rails.root.join("app/api_contract")
  end

  def fire_to_prepare!
    Rails.application.reloader.prepare!
  end

  describe "Scenario 1: Registry reload fails — error names the file" do
    let(:broken_path) { dummy_contract_dir.join("operations/zz_broken.rb") }

    before do
      File.write(broken_path, "raise SyntaxError, \"boom from spec\"\n")
    end

    after do
      FileUtils.rm_f(broken_path)
    end

    it "raises Trane::Error with the broken file path and preserves cause" do
      expect { fire_to_prepare! }.to raise_error(Trane::Error) do |error|
        expect(error.message).to include("failed to load contract files in to_prepare")
        expect(error.message).to include("zz_broken.rb")
        expect(error.cause).to be_a(SyntaxError)
        expect(error.cause.message).to include("boom from spec")
      end
    end
  end

  describe "Scenario 2: BootValidator already-Trane::Error passes through unwrapped" do
    before do
      allow(Rails.application.config).to receive(:eager_load).and_return(true)
      allow(Trane::Registry).to receive(:validate!)
        .and_raise(Trane::Error, "Trane boot validation failed:\n  operation :x references representation :y, which does not exist")
    end

    it "re-raises the original Trane::Error without re-wrapping" do
      expect { fire_to_prepare! }.to raise_error(Trane::Error) do |error|
        expect(error.message).to start_with("Trane boot validation failed:")
        expect(error.message).not_to include("BootValidator raised an unexpected error type")
        expect(error.cause).to be_nil
      end
    end
  end

  describe "Scenario 2b: BootValidator raising non-Trane::Error is wrapped" do
    before do
      allow(Rails.application.config).to receive(:eager_load).and_return(true)
      allow(Trane::Registry).to receive(:validate!).and_raise(RuntimeError, "internal bug")
    end

    it "wraps the unexpected exception in Trane::Error with cause preserved" do
      expect { fire_to_prepare! }.to raise_error(Trane::Error) do |error|
        expect(error.message).to include("BootValidator raised an unexpected error type")
        expect(error.message).to include("RuntimeError: internal bug")
        expect(error.cause).to be_a(RuntimeError)
      end
    end
  end

  describe "Scenario 4: Happy path is unchanged" do
    it "does not raise and leaves the registry populated" do
      expect { fire_to_prepare! }.not_to raise_error
      expect(Trane::Registry.operations).not_to be_empty
      expect(Trane::Registry.representations).not_to be_empty
    end
  end

  describe "Scenario 5: BootValidator skipped when eager_load is false" do
    before do
      allow(Rails.application.config).to receive(:eager_load).and_return(false)
    end

    it "does not call Registry.validate! during to_prepare" do
      expect(Trane::Registry).not_to receive(:validate!)
      expect { fire_to_prepare! }.not_to raise_error
    end
  end

  describe "Scenario 6: docs cache is computed lazily, not eagerly during to_prepare" do
    # During to_prepare the host routes are not drawn yet — it runs before
    # set_routes_reloader_hook, in every environment (confirmed empirically:
    # 0 routes even in after_initialize under eager_load). Eagerly precomputing
    # there caches a doc with every operation defaulting to GET and an empty
    # path (the original bug, reproduced in dev and prod). to_prepare must
    # invalidate the cache instead, so the first post-boot read — inside a
    # request, with the routes drawn — computes the correct snapshot lazily.
    it "invalidates the docs cache during to_prepare so the next read recomputes it" do
      Trane::Docs::Cache.precompute! # simulate an already-populated cache

      fire_to_prepare!

      expect(Trane::Docs::Cache).to receive(:precompute!).and_call_original
      Trane::Docs::Cache.json
    end
  end
end
