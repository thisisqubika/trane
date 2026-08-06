# frozen_string_literal: true

RSpec.describe Trane::Types do
  describe ".primitive?" do
    it "returns true for nil" do
      expect(described_class.primitive?(nil)).to be true
    end

    it "returns true for primitive types" do
      %i[string integer float boolean date datetime object array].each do |type|
        expect(described_class.primitive?(type)).to be(true), "Expected #{type} to be primitive"
      end
    end

    it "treats :any as a representation reference (no longer primitive)" do
      expect(described_class.primitive?(:any)).to be(false)
      expect(described_class.representation_reference?(:any)).to be(true)
    end

    it "treats :dynamic as a representation reference (no longer primitive)" do
      expect(described_class.primitive?(:dynamic)).to be(false)
      expect(described_class.representation_reference?(:dynamic)).to be(true)
    end

    it "returns false for representation references" do
      expect(described_class.primitive?(:user)).to be false
      expect(described_class.primitive?(:car)).to be false
    end
  end

  describe ".representation_reference?" do
    it "returns false for nil" do
      expect(described_class.representation_reference?(nil)).to be false
    end

    it "returns false for primitive types" do
      expect(described_class.representation_reference?(:string)).to be false
      expect(described_class.representation_reference?(:integer)).to be false
    end

    it "returns true for non-primitive symbols" do
      expect(described_class.representation_reference?(:user)).to be true
      expect(described_class.representation_reference?(:car)).to be true
      expect(described_class.representation_reference?(:address)).to be true
    end
  end

  describe ".value_matches_type?" do
    it "matches string" do
      expect(described_class.value_matches_type?("hello", :string)).to be true
      expect(described_class.value_matches_type?(1, :string)).to be false
    end

    it "matches integer strictly (no float coercion)" do
      expect(described_class.value_matches_type?(1, :integer)).to be true
      expect(described_class.value_matches_type?(1.0, :integer)).to be false
    end

    it "matches float strictly (no integer coercion)" do
      expect(described_class.value_matches_type?(1.0, :float)).to be true
      expect(described_class.value_matches_type?(1, :float)).to be false
    end

    it "matches boolean (true and false)" do
      expect(described_class.value_matches_type?(true, :boolean)).to be true
      expect(described_class.value_matches_type?(false, :boolean)).to be true
      expect(described_class.value_matches_type?(nil, :boolean)).to be false
    end

    it "matches Date but not DateTime for :date" do
      expect(described_class.value_matches_type?(Date.today, :date)).to be true
      expect(described_class.value_matches_type?(DateTime.now, :date)).to be false
    end

    it "matches DateTime and Time for :datetime" do
      expect(described_class.value_matches_type?(DateTime.now, :datetime)).to be true
      expect(described_class.value_matches_type?(Time.now, :datetime)).to be true
      expect(described_class.value_matches_type?(Date.today, :datetime)).to be false
    end

    if defined?(ActiveSupport::TimeWithZone)
      it "matches ActiveSupport::TimeWithZone for :datetime" do
        twz = ActiveSupport::TimeWithZone.new(Time.now.utc, ActiveSupport::TimeZone["UTC"])
        expect(described_class.value_matches_type?(twz, :datetime)).to be true
      end
    end

    it "returns false for unknown types" do
      expect(described_class.value_matches_type?("x", :unknown)).to be false
    end
  end

  describe ".validate_enum!" do
    it "does nothing when enum is nil" do
      expect { described_class.validate_enum!(name: :x, type: :string, enum: nil) }.not_to raise_error
    end

    it "raises when enum is not an Array" do
      expect {
        described_class.validate_enum!(name: :x, type: :string, enum: "foo")
      }.to raise_error(ArgumentError, /must be an Array/)
    end

    it "raises when enum is an empty Array" do
      expect {
        described_class.validate_enum!(name: :x, type: :string, enum: [])
      }.to raise_error(ArgumentError, /non-empty/)
    end

    it "raises when type is :array" do
      expect {
        described_class.validate_enum!(name: :x, type: :array, enum: [ "a" ])
      }.to raise_error(ArgumentError, /scalar primitive/)
    end

    it "raises when type is :object" do
      expect {
        described_class.validate_enum!(name: :x, type: :object, enum: [ "a" ])
      }.to raise_error(ArgumentError, /scalar primitive/)
    end

    it "raises when type is a representation reference" do
      expect {
        described_class.validate_enum!(name: :x, type: :user, enum: [ "a" ])
      }.to raise_error(ArgumentError, /scalar primitive/)
    end

    it "raises when an enum value type mismatches :integer" do
      expect {
        described_class.validate_enum!(name: :x, type: :integer, enum: [ 1, 1.0 ])
      }.to raise_error(ArgumentError, /1\.0 \(Float\)/)
    end

    it "does not raise for valid :string enum" do
      expect {
        described_class.validate_enum!(name: :x, type: :string, enum: [ "a", "b" ])
      }.not_to raise_error
    end

    it "does not raise for valid :integer enum" do
      expect {
        described_class.validate_enum!(name: :x, type: :integer, enum: [ 1, 2, 3 ])
      }.not_to raise_error
    end

    it "does not raise for valid :float enum" do
      expect {
        described_class.validate_enum!(name: :x, type: :float, enum: [ 1.0, 2.5 ])
      }.not_to raise_error
    end

    it "does not raise for valid :boolean enum" do
      expect {
        described_class.validate_enum!(name: :x, type: :boolean, enum: [ true, false ])
      }.not_to raise_error
    end

    it "does not raise for valid :date enum" do
      expect {
        described_class.validate_enum!(name: :x, type: :date, enum: [ Date.today ])
      }.not_to raise_error
    end

    it "raises when DateTime is passed for :date type" do
      expect {
        described_class.validate_enum!(name: :x, type: :date, enum: [ DateTime.now ])
      }.to raise_error(ArgumentError, /not coherent with type :date/)
    end

    it "does not raise for valid :datetime enum with DateTime" do
      expect {
        described_class.validate_enum!(name: :x, type: :datetime, enum: [ DateTime.now ])
      }.not_to raise_error
    end

    it "raises when plain Date is passed for :datetime type" do
      expect {
        described_class.validate_enum!(name: :x, type: :datetime, enum: [ Date.today ])
      }.to raise_error(ArgumentError, /not coherent with type :datetime/)
    end
  end
end
