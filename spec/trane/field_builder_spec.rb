# frozen_string_literal: true

RSpec.describe Trane::FieldBuilder do
  subject(:builder) { described_class.new }

  describe "#field" do
    it "builds a simple typed field" do
      builder.field :name, type: :string
      field = builder.fields.first

      expect(field.name).to eq(:name)
      expect(field.type).to eq(:string)
      expect(field.extra).to be false
    end

    it "builds a field with extra: true" do
      builder.field :alias, type: :string, extra: true
      field = builder.fields.first

      expect(field.extra).to be true
    end

    it "builds a field with format" do
      builder.field :birthday, type: :date, format: :iso8601
      field = builder.fields.first

      expect(field.format).to eq(:iso8601)
    end

    it "builds an array field with of:" do
      builder.field :users, type: :array, of: :user
      field = builder.fields.first

      expect(field.type).to eq(:array)
      expect(field.array_of).to eq(:user)
    end

    it "infers :array type when of: is provided without explicit type" do
      builder.field :tags, of: :string
      field = builder.fields.first

      expect(field.type).to eq(:array)
      expect(field.array_of).to eq(:string)
    end

    it "builds an inline nested object with block" do
      builder.field :address do
        field :street, type: :string
        field :city, type: :string
      end
      field = builder.fields.first

      expect(field.type).to eq(:object)
      expect(field.children.length).to eq(2)
      expect(field.children.first.name).to eq(:street)
      expect(field.children.last.name).to eq(:city)
    end

    it "builds deeply nested fields" do
      builder.field :user do
        field :address do
          field :street, type: :string
        end
      end

      user = builder.fields.first
      address = user.children.first
      street = address.children.first

      expect(user.type).to eq(:object)
      expect(address.type).to eq(:object)
      expect(street.type).to eq(:string)
    end

    it "builds a field referencing a representation" do
      builder.field :user, type: :user
      field = builder.fields.first

      expect(field.type).to eq(:user)
    end

    it "accumulates multiple fields" do
      builder.field :id, type: :integer
      builder.field :name, type: :string
      builder.field :email, type: :string

      expect(builder.fields.length).to eq(3)
    end

    it "raises ArgumentError when called without type:, of:, or block" do
      expect { builder.field :foo }.to raise_error(ArgumentError, /:foo/)
    end

    describe "field name validation" do
      it "raises ArgumentError for nil field name" do
        expect { builder.field(nil, type: :string) }
          .to raise_error(ArgumentError, /field name cannot be nil or empty/)
      end

      it "raises ArgumentError for empty field name" do
        expect { builder.field("", type: :string) }
          .to raise_error(ArgumentError, /field name cannot be nil or empty/)
      end
    end

    it "accepts type: :array combined with of: shortcut" do
      builder.field :tags, type: :array, of: :string
      field = builder.fields.first

      expect(field.type).to eq(:array)
      expect(field.array_of).to eq(:string)
    end

    it "raises ArgumentError for the old positional form" do
      expect { builder.field :name, :string }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when required: is passed in a representation context" do
      expect {
        Trane.representation :bad_rep do
          field :name, type: :string, required: true
        end
      }.to raise_error(ArgumentError, /unknown keyword: :?required/)
    end

    it "raises ArgumentError when required: is passed in a response context" do
      expect {
        Trane.operation :bad_response_op do
          response 200 do
            field :user, type: :user, required: true
          end
        end
      }.to raise_error(ArgumentError, /unknown keyword: :?required/)
    end

    it "builds a field with enum:" do
      builder.field :status, type: :string, enum: ["active", "archived"]
      field = builder.fields.first

      expect(field.enum).to eq(["active", "archived"])
    end

    it "raises ArgumentError when enum values do not match the declared type" do
      expect {
        builder.field :count, type: :integer, enum: [1.0]
      }.to raise_error(ArgumentError, /not coherent with type :integer/)
    end
  end

  describe "#_resolve_type (private)" do
    it "raises ArgumentError when all type specifiers are absent" do
      expect { builder.send(:_resolve_type, nil, nil, false) }
        .to raise_error(ArgumentError, /precondition bypassed/)
    end
  end
end
