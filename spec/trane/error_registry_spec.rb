# frozen_string_literal: true

RSpec.describe "Error DSL" do
  describe Trane::ErrorsBuilder do
    it "builds error definitions" do
      builder = described_class.new
      builder.error :UserNotFound, status_code: 404, description: "User not found"
      builder.error :UserInvalid, status_code: 422, description: "User is invalid"

      expect(builder.definitions.length).to eq(2)

      first = builder.definitions.first
      expect(first.key).to eq("UserNotFound")
      expect(first.status_code).to eq(404)
      expect(first.description).to eq("User not found")
    end

    it "accepts a string FQDN key" do
      builder = described_class.new
      builder.error "Errors::UserNotFound", status_code: 404, description: "User not found"

      expect(builder.definitions.first.key).to eq("Errors::UserNotFound")
    end

    it "accepts a Class and uses Class#name as the key" do
      stub_const("Errors::ArtistNotFound", Class.new(StandardError))
      builder = described_class.new
      builder.error Errors::ArtistNotFound, status_code: 404, description: "Artist not found"

      expect(builder.definitions.first.key).to eq("Errors::ArtistNotFound")
    end

    it "accepts description: as optional" do
      builder = described_class.new
      builder.error :Foo, status_code: 404

      expect(builder.definitions.first.key).to eq("Foo")
      expect(builder.definitions.first.description).to be_nil
    end
  end

  describe Trane::ErrorDefinition do
    it "converts key to string" do
      err = described_class.new(key: :UserNotFound, status_code: 404, description: "Not found")
      expect(err.key).to eq("UserNotFound")
    end

    it "preserves FQDN string keys" do
      err = described_class.new(key: "Errors::UserNotFound", status_code: 404, description: "Not found")
      expect(err.key).to eq("Errors::UserNotFound")
    end

    it "converts status_code to integer" do
      err = described_class.new(key: :UserNotFound, status_code: "404", description: "Not found")
      expect(err.status_code).to eq(404)
    end

    it "accepts nil description" do
      err = described_class.new(key: :UserNotFound, status_code: 404)
      expect(err.description).to be_nil
    end
  end

  describe "ErrorDefinition status_code validation" do
    it "raises ArgumentError for status_code below 100" do
      expect { Trane::ErrorDefinition.new(key: "Foo", status_code: 99) }
        .to raise_error(ArgumentError, /not a valid HTTP status code/)
    end

    it "raises ArgumentError for status_code above 599" do
      expect { Trane::ErrorDefinition.new(key: "Foo", status_code: 600) }
        .to raise_error(ArgumentError, /not a valid HTTP status code/)
    end
  end

  describe "Trane.errors" do
    it "registers all errors in the registry" do
      Trane.errors do
        error :UserNotFound, status_code: 404, description: "User not found"
        error :UserInvalid, status_code: 422, description: "User is invalid"
        error :CarNotFound, status_code: 404, description: "Car not found"
      end

      expect(Trane::Registry.errors.keys).to contain_exactly("UserNotFound", "UserInvalid", "CarNotFound")
      expect(Trane::Registry.errors["UserNotFound"].status_code).to eq(404)
      expect(Trane::Registry.errors["UserInvalid"].status_code).to eq(422)
    end

    it "registers FQDN string keys and looks them up by FQDN" do
      Trane.errors do
        error "Errors::UserNotFound", status_code: 404, description: "User not found"
      end

      expect(Trane::Registry.errors["Errors::UserNotFound"].key).to eq("Errors::UserNotFound")
    end
  end
end
