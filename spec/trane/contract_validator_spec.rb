# frozen_string_literal: true

RSpec.describe Trane::ContractValidator do
  before do
    Trane.representation :user do
      field :id, type: :integer
      field :name, type: :string
      field :nickname, type: :string, extra: true
    end
  end

  def build_response(status, &block)
    builder = Trane::ResponseBuilder.new(status)
    builder.instance_eval(&block)
    builder.build
  end

  describe ".validate_response!" do
    let(:response_def) do
      build_response(200) do
        field :user, type: :user
        field :count, type: :integer
      end
    end

    context "with a valid response" do
      it "does not raise" do
        result = { user: { id: 1, name: "Alice" }, count: 5 }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.not_to raise_error
      end
    end

    context "with a missing declared field" do
      it "raises ContractViolation" do
        result = { user: { id: 1, name: "Alice" } }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.to raise_error(Trane::ContractViolation, /count: missing from response/)
      end
    end

    context "with an undeclared field" do
      it "raises ContractViolation" do
        result = { user: { id: 1, name: "Alice" }, count: 5, extra_field: "oops" }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.to raise_error(Trane::ContractViolation, /extra_field: undeclared field/)
      end
    end

    context "with missing field inside a representation" do
      it "raises with nested path" do
        result = { user: { id: 1 }, count: 5 }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.to raise_error(Trane::ContractViolation, /user\.name: missing from response/)
      end
    end

    context "with extra fields not requested (extra: true excluded from result)" do
      it "does not raise when extra fields are absent" do
        result = { user: { id: 1, name: "Alice" }, count: 5 }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.not_to raise_error
      end
    end

    context "with extra fields present in result" do
      it "does not raise when extra fields are included" do
        result = { user: { id: 1, name: "Alice", nickname: "Ali" }, count: 5 }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.not_to raise_error
      end
    end

    context "with mode :log" do
      it "logs a warning instead of raising" do
        result = { user: { id: 1, name: "Alice" } }

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          expect(Rails.logger).to receive(:warn).with(/Trane contract violations/)
        else
          expect {
            described_class.validate_response!(response_def, result, Trane::Registry, mode: :log)
          }.to output(/Trane contract violations/).to_stderr
          return
        end

        described_class.validate_response!(response_def, result, Trane::Registry, mode: :log)
      end
    end

    context "with mode :ignore" do
      it "does nothing (ignore mode is handled by the Serializer, not the validator)" do
        # The Serializer skips calling validate_response! entirely for :ignore mode.
        # If called directly with :ignore, the validator finds violations but does nothing.
        result = {}
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :ignore)
        }.not_to raise_error
      end
    end

    context "violation messages" do
      it "include the response status code" do
        result = { user: { id: 1, name: "Alice" } }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.to raise_error(Trane::ContractViolation, /Trane contract violations \(status 200\):/)
      end
    end

    context "with :object type field (passthrough)" do
      it "does not recurse into :object fields without children" do
        resp = build_response(200) { field :data, type: :object }
        result = { data: { unexpected_key: "ok", nested: [ 1, 2, 3 ] } }

        expect {
          described_class.validate_response!(resp, result, Trane::Registry, mode: :raise)
        }.not_to raise_error
      end
    end

    context "with nil values in result" do
      it "does not recurse into nil values" do
        result = { user: nil, count: 5 }
        expect {
          described_class.validate_response!(response_def, result, Trane::Registry, mode: :raise)
        }.not_to raise_error
      end
    end
  end
end
