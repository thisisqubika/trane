# frozen_string_literal: true

RSpec.describe "Representation DSL" do
  describe Trane::RepresentationBuilder do
    it "builds a representation with simple fields" do
      builder = described_class.new(:user)
      builder.instance_eval do
        field :id, type: :integer
        field :name, type: :string
        field :email, type: :string
      end
      rep = builder.build

      expect(rep.name).to eq(:user)
      expect(rep.fields.length).to eq(3)
      expect(rep.fields.map(&:name)).to eq([ :id, :name, :email ])
    end

    it "builds a representation with format" do
      builder = described_class.new(:user)
      builder.instance_eval do
        field :created_at, type: :datetime, format: :iso8601
      end
      rep = builder.build

      expect(rep.fields.first.format).to eq(:iso8601)
    end

    it "builds a representation with extra fields" do
      builder = described_class.new(:user)
      builder.instance_eval do
        field :id, type: :integer
        field :alias, type: :string, extra: true
      end
      rep = builder.build

      expect(rep.fields[0].extra).to be false
      expect(rep.fields[1].extra).to be true
    end

    it "builds a representation with array fields" do
      builder = described_class.new(:user)
      builder.instance_eval do
        field :hobbies, type: :array, of: :string
        field :pets, type: :array, of: :pet
      end
      rep = builder.build

      expect(rep.fields[0].type).to eq(:array)
      expect(rep.fields[0].array_of).to eq(:string)
      expect(rep.fields[1].array_of).to eq(:pet)
    end
  end

  describe "RepresentationDefinition name validation" do
    it "raises ArgumentError for nil name" do
      expect { Trane::RepresentationDefinition.new(name: nil) }
        .to raise_error(ArgumentError, /name cannot be nil or empty/)
    end

    it "raises ArgumentError for empty string name" do
      expect { Trane::RepresentationDefinition.new(name: "") }
        .to raise_error(ArgumentError, /name cannot be nil or empty/)
    end
  end

  describe "Trane.representation" do
    it "registers a representation in the registry" do
      Trane.representation :user do
        field :id, type: :integer
        field :name, type: :string
        field :email, type: :string
        field :birthday, type: :date, format: :iso8601
        field :created_at, type: :datetime, format: :iso8601
      end

      rep = Trane::Registry.representations[:user]
      expect(rep).to be_a(Trane::RepresentationDefinition)
      expect(rep.name).to eq(:user)
      expect(rep.fields.length).to eq(5)
    end
  end
end
