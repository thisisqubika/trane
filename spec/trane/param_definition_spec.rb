# frozen_string_literal: true

RSpec.describe Trane::ParamDefinition do
  it "creates a path param" do
    param = described_class.new(name: :id, type: :integer, required: true, location: :path)

    expect(param.name).to eq(:id)
    expect(param.type).to eq(:integer)
    expect(param.required).to be true
    expect(param.location).to eq(:path)
  end

  it "defaults required to false for query location" do
    param = described_class.new(name: :status, type: :string, location: :query)

    expect(param.required).to be false
  end

  it "defaults required to false for path location (DSL overrides to true)" do
    param = described_class.new(name: :id, type: :integer, location: :path)

    expect(param.required).to be false
  end

  it "creates a query param" do
    param = described_class.new(name: :status, type: :string, location: :query)

    expect(param.location).to eq(:query)
  end

  it "converts name and type to symbols" do
    param = described_class.new(name: "id", type: "integer", location: "path")

    expect(param.name).to eq(:id)
    expect(param.type).to eq(:integer)
    expect(param.location).to eq(:path)
  end

  it "defaults enum to nil" do
    param = described_class.new(name: :status, type: :string, location: :query)
    expect(param.enum).to be_nil
  end

  it "accepts enum: and returns the frozen array" do
    param = described_class.new(name: :x, type: :string, location: :query, enum: ["a"])
    expect(param.enum).to eq(["a"])
    expect(param.enum).to be_frozen
  end
end
