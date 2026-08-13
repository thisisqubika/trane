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

  describe "cache growth bound" do
    def transient_response_def(status)
      Trane::ResponseBuilder.new(status).tap do |b|
        b.field :id, type: :integer
      end.build
    end

    it "stops caching serializers past MAX_CACHE_ENTRIES but keeps returning working ones" do
      stub_const("Trane::Registry::Instance::MAX_CACHE_ENTRIES", 2)

      serializers = Array.new(4) { instance.compiled_serializer_for(transient_response_def(200), :raise) }

      expect(instance.instance_variable_get(:@compiled_serializers).size).to be <= 2
      expect(serializers).to all(be_a(Trane::Serializer))
      expect(serializers.last.serialize({ id: 7 })).to eq({ id: 7 })
    end

    it "stops caching validator field names past MAX_CACHE_ENTRIES but keeps returning correct ones" do
      stub_const("Trane::Registry::Instance::MAX_CACHE_ENTRIES", 2)

      names = Array.new(4) do |i|
        fields = [ Trane::FieldNode.new(name: :"field_#{i}", type: :integer) ].freeze
        instance.validator_field_names_for(fields)
      end

      expect(instance.instance_variable_get(:@validator_field_names).size).to be <= 2
      expect(names.last).to eq([ :field_3 ])
    end

    it "stops caching declared field names past MAX_CACHE_ENTRIES but keeps returning correct ones" do
      stub_const("Trane::Registry::Instance::MAX_CACHE_ENTRIES", 2)

      names = Array.new(4) do |i|
        fields = [
          Trane::FieldNode.new(name: :"declared_#{i}", type: :integer),
          Trane::FieldNode.new(name: :extra_one, type: :string, extra: true)
        ].freeze
        instance.validator_declared_field_names_for(fields)
      end

      expect(instance.instance_variable_get(:@validator_declared_field_names).size).to be <= 2
      expect(names.last).to eq([ :declared_3 ])
    end
  end
end
