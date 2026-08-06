# frozen_string_literal: true

RSpec.describe Trane::FieldNode do
  describe "initialization" do
    it "creates a field node with minimal args" do
      node = described_class.new(name: :id)
      expect(node.name).to eq(:id)
      expect(node.type).to be_nil
      expect(node.extra).to be false
      expect(node.format).to be_nil
      expect(node.array_of).to be_nil
      expect(node.required).to be_nil
      expect(node.children).to eq([])
    end

    it "creates a field node with all args" do
      child = described_class.new(name: :street, type: :string)
      node = described_class.new(
        name: :address,
        type: :object,
        extra: true,
        format: :iso8601,
        array_of: :string,
        required: true,
        children: [child]
      )

      expect(node.name).to eq(:address)
      expect(node.type).to eq(:object)
      expect(node.extra).to be true
      expect(node.format).to eq(:iso8601)
      expect(node.array_of).to eq(:string)
      expect(node.required).to be true
      expect(node.children).to eq([child])
    end

    it "defaults required to nil" do
      expect(described_class.new(name: :x).required).to be_nil
    end

    it "accepts required: true" do
      expect(described_class.new(name: :x, required: true).required).to be true
    end

    it "accepts required: false" do
      expect(described_class.new(name: :x, required: false).required).to be false
    end

    it "defaults enum to nil" do
      expect(described_class.new(name: :x).enum).to be_nil
    end

    it "accepts enum: and returns the array" do
      node = described_class.new(name: :x, enum: ["a", "b"])
      expect(node.enum).to eq(["a", "b"])
    end

    it "freezes the enum array" do
      node = described_class.new(name: :x, enum: ["a", "b"])
      expect(node.enum).to be_frozen
    end

    it "converts name to symbol" do
      node = described_class.new(name: "id")
      expect(node.name).to eq(:id)
    end

    it "converts type to symbol" do
      node = described_class.new(name: :id, type: "string")
      expect(node.type).to eq(:string)
    end

    it "freezes children" do
      node = described_class.new(name: :test, children: [])
      expect(node.children).to be_frozen
    end
  end
end
