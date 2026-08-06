# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trane::Registry::Instance do
  let(:instance) { described_class.new }

  def make_fields(*specs)
    specs.map do |name, extra|
      Trane::FieldNode.new(name: name, type: :string, extra: extra || false)
    end.freeze
  end

  let(:fields_a) { make_fields([:id, false], [:name, false], [:nickname, true]) }
  let(:fields_b) { make_fields([:title, false], [:body, false]) }

  describe "#validator_field_names_for" do
    it "returns the same Array identity on repeated calls" do
      arr1 = instance.validator_field_names_for(fields_a)
      arr2 = instance.validator_field_names_for(fields_a)
      expect(arr1).to be(arr2)
    end

    it "returns a frozen Array" do
      expect(instance.validator_field_names_for(fields_a).frozen?).to be true
    end

    it "returns distinct Arrays for different fields collections" do
      arr_a = instance.validator_field_names_for(fields_a)
      arr_b = instance.validator_field_names_for(fields_b)
      expect(arr_a).not_to be(arr_b)
    end

    it "includes extra: true fields" do
      arr = instance.validator_field_names_for(fields_a)
      expect(arr).to eq(%i[id name nickname])
    end

    it "invalidates the cache on replace!" do
      arr1 = instance.validator_field_names_for(fields_a)
      instance.replace! { |_b| }
      arr2 = instance.validator_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_operation (CoW path)" do
      arr1 = instance.validator_field_names_for(fields_a)
      instance.register_operation(Trane::OperationDefinition.new(name: :cow_op))
      arr2 = instance.validator_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_representation (CoW path)" do
      arr1 = instance.validator_field_names_for(fields_a)
      instance.register_representation(Trane::RepresentationDefinition.new(name: :cow_rep, fields: []))
      arr2 = instance.validator_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_error (CoW path)" do
      arr1 = instance.validator_field_names_for(fields_a)
      instance.register_error(Trane::ErrorDefinition.new(key: :CowErr, status_code: 500, description: "x"))
      arr2 = instance.validator_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end
  end

  describe "#validator_declared_field_names_for" do
    it "returns the same Array identity on repeated calls" do
      arr1 = instance.validator_declared_field_names_for(fields_a)
      arr2 = instance.validator_declared_field_names_for(fields_a)
      expect(arr1).to be(arr2)
    end

    it "returns a frozen Array" do
      expect(instance.validator_declared_field_names_for(fields_a).frozen?).to be true
    end

    it "returns distinct Arrays for different fields collections" do
      arr_a = instance.validator_declared_field_names_for(fields_a)
      arr_b = instance.validator_declared_field_names_for(fields_b)
      expect(arr_a).not_to be(arr_b)
    end

    it "excludes extra: true fields" do
      arr = instance.validator_declared_field_names_for(fields_a)
      expect(arr).to eq(%i[id name])
      expect(arr).not_to include(:nickname)
    end

    it "invalidates the cache on replace!" do
      arr1 = instance.validator_declared_field_names_for(fields_a)
      instance.replace! { |_b| }
      arr2 = instance.validator_declared_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_operation (CoW path)" do
      arr1 = instance.validator_declared_field_names_for(fields_a)
      instance.register_operation(Trane::OperationDefinition.new(name: :cow_op2))
      arr2 = instance.validator_declared_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_representation (CoW path)" do
      arr1 = instance.validator_declared_field_names_for(fields_a)
      instance.register_representation(Trane::RepresentationDefinition.new(name: :cow_rep2, fields: []))
      arr2 = instance.validator_declared_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end

    it "invalidates the cache on register_error (CoW path)" do
      arr1 = instance.validator_declared_field_names_for(fields_a)
      instance.register_error(Trane::ErrorDefinition.new(key: :CowErr2, status_code: 500, description: "x"))
      arr2 = instance.validator_declared_field_names_for(fields_a)
      expect(arr1).not_to be(arr2)
    end
  end

  describe "extra: filtering contrast" do
    it "validator_field_names_for includes extra fields while validator_declared_field_names_for excludes them" do
      all_names      = instance.validator_field_names_for(fields_a)
      declared_names = instance.validator_declared_field_names_for(fields_a)

      expect(all_names).to include(:nickname)
      expect(declared_names).not_to include(:nickname)
    end
  end

  describe "allocation budget (cache hit path)", skip: RUBY_ENGINE != "ruby" do
    it "allocates fewer objects per validate call than the uncached set-chain approach" do
      iterations = 2_000

      Trane::Registry.reset!
      Trane.representation :alloc_spec_inner do
        field :id,   type: :integer
        field :name, type: :string
        field :tag,  type: :string, extra: true
      end
      Trane.representation :alloc_spec_outer do
        field :id,    type: :integer
        field :title, type: :string
        field :inner, type: :alloc_spec_inner
        field :note,  type: :string, extra: true
      end

      response_def = Trane::ResponseBuilder.new(200).tap do |b|
        b.field :item,  type: :alloc_spec_outer
        b.field :count, type: :integer
      end.build

      data = { item: { id: 1, title: "T", inner: { id: 2, name: "S" } }, count: 1 }
      registry = Trane.registry

      Trane::ContractValidator.validate_response!(response_def, data, registry, mode: :ignore)

      GC.disable
      before = GC.stat[:total_allocated_objects]
      iterations.times { Trane::ContractValidator.validate_response!(response_def, data, registry, mode: :ignore) }
      new_allocs = (GC.stat[:total_allocated_objects] - before).to_f / iterations
      GC.enable

      old_allocs_per_call = 14.0

      expect(new_allocs).to be < (old_allocs_per_call - 4)
    end
  end
end
