# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trane::Registry::Instance do
  let(:instance) { described_class.new }

  let(:response_def_a) do
    Trane::ResponseBuilder.new(200).tap do |b|
      b.field :id, type: :integer
    end.build
  end

  let(:response_def_b) do
    Trane::ResponseBuilder.new(404).tap do |b|
      b.field :error, type: :string
    end.build
  end

  describe "#compiled_serializer_for" do
    it "returns the same Serializer instance for the same (ResponseDefinition, strict_mode)" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).to be(s2)
    end

    it "returns different instances for different strict_modes" do
      s_raise = instance.compiled_serializer_for(response_def_a, :raise)
      s_log   = instance.compiled_serializer_for(response_def_a, :log)
      expect(s_raise).not_to be(s_log)
    end

    it "returns different instances for different ResponseDefinitions" do
      s_a = instance.compiled_serializer_for(response_def_a, :raise)
      s_b = instance.compiled_serializer_for(response_def_b, :raise)
      expect(s_a).not_to be(s_b)
    end

    it "invalidates the cache on replace!" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      instance.replace! { |_b| }
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).not_to be(s2)
    end

    it "invalidates the cache on reset!" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      instance.reset!
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).not_to be(s2)
    end

    it "invalidates the cache on register_operation (CoW path)" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      instance.register_operation(Trane::OperationDefinition.new(name: :cow_op))
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).not_to be(s2)
    end

    it "invalidates the cache on register_representation (CoW path)" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      instance.register_representation(Trane::RepresentationDefinition.new(name: :cow_rep, fields: []))
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).not_to be(s2)
    end

    it "invalidates the cache on register_error (CoW path)" do
      s1 = instance.compiled_serializer_for(response_def_a, :raise)
      instance.register_error(Trane::ErrorDefinition.new(key: :CowErr, status_code: 500, description: "x"))
      s2 = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s1).not_to be(s2)
    end

    it "returns a frozen Serializer" do
      s = instance.compiled_serializer_for(response_def_a, :raise)
      expect(s.frozen?).to be true
      expect { s.instance_variable_set(:@foo, 1) }.to raise_error(FrozenError)
    end
  end
end
