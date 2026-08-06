# frozen_string_literal: true

RSpec.describe Trane::ExtraAttributesFilter do
  describe ".parse" do
    it "returns empty set for nil params" do
      result = described_class.parse({})
      expect(result).to eq(Set.new)
    end

    it "returns empty set for nil extra_attributes" do
      result = described_class.parse({ extra_attributes: nil })
      expect(result).to eq(Set.new)
    end

    it "parses an array of extra attributes" do
      result = described_class.parse({ extra_attributes: ["user.alias", "user.address.zip_code"] })
      expect(result).to eq(Set["user.alias", "user.address.zip_code"])
    end

    it "parses a single string extra attribute" do
      result = described_class.parse({ extra_attributes: "user.alias" })
      expect(result).to eq(Set["user.alias"])
    end

    it "handles non-array non-string values" do
      result = described_class.parse({ extra_attributes: 123 })
      expect(result).to eq(Set.new)
    end

    it "accepts values within the cap" do
      values = ("a".."z").to_a
      result = described_class.parse({ extra_attributes: values })
      expect(result.size).to eq(26)
      expect(result).to include("a", "z")
    end

    it "truncates at MAX_VALUES, keeping the first N after coercion" do
      values = (1..200).map { |i| "f#{i}" }
      result = described_class.parse({ extra_attributes: values })
      expect(result.size).to eq(100)
      expect(result).to include("f1", "f100")
      expect(result).not_to include("f101", "f200")
    end

    it "does not truncate a single String input character-wise" do
      long = "a" * 250
      result = described_class.parse({ extra_attributes: long })
      expect(result).to eq(Set[long])
    end

    it "returns the same frozen sentinel across calls for nil params" do
      result_a = described_class.parse({})
      result_b = described_class.parse({})
      expect(result_a).to equal(result_b)
      expect(result_a).to be_frozen
    end

    it "returns the sentinel for non-iterable input" do
      expect(described_class.parse({ extra_attributes: 42 }))
        .to equal(Trane::ExtraAttributesFilter::EMPTY)
    end

    it "returns the sentinel for empty array input" do
      expect(described_class.parse({ extra_attributes: [] }))
        .to equal(Trane::ExtraAttributesFilter::EMPTY)
    end
  end
end
