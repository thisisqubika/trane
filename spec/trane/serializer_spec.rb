# frozen_string_literal: true

RSpec.describe Trane::Serializer do
  # Simple test double that responds to methods via a hash
  TestObject = Struct.new(:id, :name, :email, :birthday, :created_at, :brand, :model,
                          :alias_name, :secret_score, :address, keyword_init: true)

  before do
    Trane.representation :user do
      field :id, type: :integer
      field :name, type: :string
      field :email, type: :string
      field :birthday, type: :date, format: :iso8601
      field :created_at, type: :datetime, format: :iso8601
    end

    Trane.representation :car do
      field :id, type: :integer
      field :brand, type: :string
      field :model, type: :string
    end
  end

  def build_response(status, &block)
    builder = Trane::ResponseBuilder.new(status)
    builder.instance_eval(&block)
    builder.build
  end

  def make_user(**attrs)
    defaults = { id: nil, name: nil, email: nil, birthday: nil, created_at: nil }
    Struct.new(*defaults.keys, keyword_init: true).new(**defaults.merge(attrs))
  end

  describe "default extra_attributes argument" do
    it "behaves identically whether omitted or explicitly set to EMPTY sentinel" do
      Trane.representation :default_arg_user do
        field :id,    type: :integer
        field :alias, type: :string, extra: true
      end
      response_def = build_response(200) { field :user, type: :default_arg_user }
      serializer = described_class.new(response_def, Trane::Registry)
      data = { user: { id: 1, alias: "hidden" } }

      result_default  = serializer.serialize(data)
      result_explicit = serializer.serialize(data, extra_attributes: Trane::ExtraAttributesFilter::EMPTY)

      expect(result_default).to eq(user: { id: 1 })
      expect(result_default[:user]).not_to have_key(:alias)
      expect(result_explicit).to eq(result_default)
    end
  end

  describe "primitive field serialization" do
    it "serializes a simple string field" do
      response_def = build_response(200) { field :message, type: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ message: "Hello" })
      expect(result).to eq({ message: "Hello" })
    end

    it "serializes multiple primitive fields" do
      response_def = build_response(200) do
        field :id, type: :integer
        field :name, type: :string
      end
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ id: 1, name: "Alice" })
      expect(result).to eq({ id: 1, name: "Alice" })
    end
  end

  describe "nil handling" do
    it "includes nil values as null" do
      response_def = build_response(200) do
        field :id, type: :integer
        field :name, type: :string
      end
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ id: 1, name: nil })
      expect(result).to eq({ id: 1, name: nil })
      expect(result.key?(:name)).to be true
    end
  end

  describe "representation lookup" do
    it "serializes an object using a representation" do
      response_def = build_response(200) { field :user, type: :user }
      serializer = described_class.new(response_def, Trane::Registry)

      user = make_user(id: 1, name: "Alice", email: "alice@test.com")
      result = serializer.serialize({ user: user })

      expect(result[:user]).to eq({
        id: 1,
        name: "Alice",
        email: "alice@test.com",
        birthday: nil,
        created_at: nil
      })
    end
  end

  describe "array serialization" do
    it "serializes an array of representations" do
      response_def = build_response(200) { field :users, type: :array, of: :user }
      serializer = described_class.new(response_def, Trane::Registry)

      users = [
        make_user(id: 1, name: "Alice", email: "a@t.com"),
        make_user(id: 2, name: "Bob", email: "b@t.com")
      ]
      result = serializer.serialize({ users: users })

      expect(result[:users].length).to eq(2)
      expect(result[:users][0][:name]).to eq("Alice")
      expect(result[:users][1][:name]).to eq("Bob")
    end

    it "serializes an array of primitives" do
      response_def = build_response(200) { field :tags, type: :array, of: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ tags: [ "ruby", "rails" ] })
      expect(result[:tags]).to eq([ "ruby", "rails" ])
    end

    it "returns nil for nil array value" do
      response_def = build_response(200) { field :items, type: :array, of: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ items: nil })
      expect(result[:items]).to be_nil
    end
  end

  describe "nested representations" do
    before do
      Trane.representation :address do
        field :street, type: :string
        field :city, type: :string
      end

      Trane.representation :profile do
        field :name, type: :string
        field :address, type: :address
      end
    end

    it "serializes nested representation references" do
      response_def = build_response(200) { field :profile, type: :profile }
      serializer = described_class.new(response_def, Trane::Registry)

      address_struct = Struct.new(:street, :city, keyword_init: true)
      profile_struct = Struct.new(:name, :address, keyword_init: true)

      data = {
        profile: profile_struct.new(
          name: "Alice",
          address: address_struct.new(street: "123 Main St", city: "Springfield")
        )
      }
      result = serializer.serialize(data)

      expect(result[:profile][:name]).to eq("Alice")
      expect(result[:profile][:address][:street]).to eq("123 Main St")
      expect(result[:profile][:address][:city]).to eq("Springfield")
    end
  end

  describe "inline children (nested objects)" do
    it "serializes inline nested objects" do
      response_def = build_response(200) do
        field :result do
          field :count, type: :integer
          field :label, type: :string
        end
      end
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ result: { count: 42, label: "test" } })
      expect(result[:result]).to eq({ count: 42, label: "test" })
    end
  end

  describe "format application" do
    it "applies iso8601 format to dates" do
      response_def = build_response(200) { field :user, type: :user }
      serializer = described_class.new(response_def, Trane::Registry)

      date = Date.new(1990, 5, 15)
      datetime = Time.new(2026, 4, 1, 12, 0, 0, "+00:00")
      user = make_user(id: 1, name: "Alice", email: "a@t.com", birthday: date, created_at: datetime)

      result = serializer.serialize({ user: user })
      expect(result[:user][:birthday]).to eq("1990-05-15")
      expect(result[:user][:created_at]).to include("2026-04-01")
    end

    it "does not apply format when value doesn't respond to iso8601" do
      response_def = build_response(200) do
        field :date, type: :string, format: :iso8601
      end
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ date: "already formatted" })
      expect(result[:date]).to eq("already formatted")
    end
  end

  describe ":object type without block (passthrough)" do
    it "passes Hash values through unchanged" do
      response_def = build_response(200) { field :data, type: :object }
      serializer = described_class.new(response_def, Trane::Registry)

      payload = { arbitrary: "structure", nested: { with: [ 1, 2 ] } }
      result = serializer.serialize({ data: payload })

      expect(result[:data]).to eq(payload)
    end

    it "passes primitive values through unchanged" do
      response_def = build_response(200) { field :data, type: :object }
      serializer = described_class.new(response_def, Trane::Registry)

      expect(serializer.serialize({ data: 42 })[:data]).to eq(42)
      expect(serializer.serialize({ data: "raw" })[:data]).to eq("raw")
      expect(serializer.serialize({ data: [ 1, 2, 3 ] })[:data]).to eq([ 1, 2, 3 ])
    end

    it "returns nil when the value is nil" do
      response_def = build_response(200) { field :data, type: :object }
      serializer = described_class.new(response_def, Trane::Registry)

      expect(serializer.serialize({ data: nil })[:data]).to be_nil
    end
  end

  describe ":object type with block (inline structure — regression)" do
    it "serializes nested fields declared inline" do
      response_def = build_response(200) do
        field :metadata, type: :object do
          field :page, type: :integer
          field :per_page, type: :integer
        end
      end
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ metadata: { page: 1, per_page: 50, ignored: "x" } })

      expect(result[:metadata]).to eq(page: 1, per_page: 50)
    end
  end

  describe "data extraction" do
    it "extracts from Hash with symbol keys" do
      response_def = build_response(200) { field :name, type: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ name: "Alice" })
      expect(result[:name]).to eq("Alice")
    end

    it "extracts from Hash with string keys" do
      response_def = build_response(200) { field :name, type: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      result = serializer.serialize({ "name" => "Alice" })
      expect(result[:name]).to eq("Alice")
    end

    it "extracts from objects via public_send" do
      response_def = build_response(200) { field :name, type: :string }
      serializer = described_class.new(response_def, Trane::Registry)

      obj = Struct.new(:name, keyword_init: true).new(name: "Alice")
      result = serializer.serialize(obj)
      expect(result[:name]).to eq("Alice")
    end

    it "returns nil for missing object methods" do
      response_def = build_response(200) do
        field :name, type: :string
        field :nonexistent, type: :string
      end
      serializer = described_class.new(response_def, Trane::Registry)

      obj = Struct.new(:name, keyword_init: true).new(name: "Alice")
      result = serializer.serialize(obj)
      expect(result[:name]).to eq("Alice")
      expect(result[:nonexistent]).to be_nil
    end
  end

  describe "extra attributes filtering" do
    before do
      Trane.representation :profile_with_extras do
        field :name, type: :string
        field :nickname, type: :string, extra: true
        field :secret_score, type: :integer, extra: true
      end
    end

    it "excludes extra fields when not requested" do
      response_def = build_response(200) { field :profile, type: :profile_with_extras }
      serializer = described_class.new(response_def, Trane::Registry)

      data = { profile: Struct.new(:name, :nickname, :secret_score, keyword_init: true)
                              .new(name: "Alice", nickname: "Ali", secret_score: 99) }
      result = serializer.serialize(data, extra_attributes: Set.new)

      expect(result[:profile].key?(:name)).to be true
      expect(result[:profile].key?(:nickname)).to be false
      expect(result[:profile].key?(:secret_score)).to be false
    end

    it "includes extra fields when requested" do
      response_def = build_response(200) { field :profile, type: :profile_with_extras }
      serializer = described_class.new(response_def, Trane::Registry)

      data = { profile: Struct.new(:name, :nickname, :secret_score, keyword_init: true)
                              .new(name: "Alice", nickname: "Ali", secret_score: 99) }
      result = serializer.serialize(data, extra_attributes: Set["profile.nickname"])

      expect(result[:profile][:name]).to eq("Alice")
      expect(result[:profile][:nickname]).to eq("Ali")
      expect(result[:profile].key?(:secret_score)).to be false
    end

    it "includes multiple extra fields when requested" do
      response_def = build_response(200) { field :profile, type: :profile_with_extras }
      serializer = described_class.new(response_def, Trane::Registry)

      data = { profile: Struct.new(:name, :nickname, :secret_score, keyword_init: true)
                              .new(name: "Alice", nickname: "Ali", secret_score: 99) }
      result = serializer.serialize(data, extra_attributes: Set["profile.nickname", "profile.secret_score"])

      expect(result[:profile][:nickname]).to eq("Ali")
      expect(result[:profile][:secret_score]).to eq(99)
    end
  end

  describe "strict array validation" do
    let(:response_def) do
      build_response(200) { field :items, type: :array, of: :string }
    end

    it "raises Trane::ContractViolation in :raise mode when value is a Hash" do
      serializer = described_class.new(response_def, Trane::Registry, strict_mode: :raise)
      expect { serializer.serialize({ items: { not: :array } }) }
        .to raise_error(Trane::ContractViolation, /expected Array at items, got Hash/)
    end

    it "raises in :raise mode when value is a String" do
      serializer = described_class.new(response_def, Trane::Registry, strict_mode: :raise)
      expect { serializer.serialize({ items: "nope" }) }
        .to raise_error(Trane::ContractViolation, /expected Array at items, got String/)
    end

    it "warns in :log mode and returns []" do
      serializer = described_class.new(response_def, Trane::Registry, strict_mode: :log)

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        expect(Rails.logger).to receive(:warn).with(/expected Array at items, got Hash/)
        result = serializer.serialize({ items: {} })
        expect(result[:items]).to eq([])
      else
        result = nil
        expect { result = serializer.serialize({ items: {} }) }
          .to output(/expected Array at items, got Hash/).to_stderr
        expect(result[:items]).to eq([])
      end
    end

    it "returns [] silently in :ignore mode" do
      serializer = described_class.new(response_def, Trane::Registry, strict_mode: :ignore)
      expect(serializer.serialize({ items: {} })[:items]).to eq([])
    end

    it "includes nested path when violation is inside a nested representation" do
      Trane.representation :container do
        field :items, type: :array, of: :string
      end
      nested_def = build_response(200) { field :container, type: :container }
      serializer = described_class.new(nested_def, Trane::Registry, strict_mode: :raise)

      container_struct = Struct.new(:items, keyword_init: true)
      expect { serializer.serialize({ container: container_struct.new(items: {}) }) }
        .to raise_error(Trane::ContractViolation, /expected Array at container\.items, got Hash/)
    end
  end

  describe "path allocation budget (audit2-08)" do
    it "allocates fewer than THRESHOLD strings over N renders with no extras and no violations" do
      Trane.representation :alloc_row do
        field :id, type: :integer
        field :a, type: :string
        field :b, type: :string
        field :c, type: :string
        field :d, type: :string
        field :e, type: :string
        field :f, type: :string
        field :g, type: :string
        field :h, type: :string
        field :i, type: :string
      end

      response_def = build_response(200) { field :rows, type: :array, of: :alloc_row }
      serializer = described_class.new(response_def, Trane::Registry)

      row_struct = Struct.new(:id, :a, :b, :c, :d, :e, :f, :g, :h, :i, keyword_init: true)
      rows = Array.new(100) { |n| row_struct.new(id: n, a: "a", b: "b", c: "c", d: "d", e: "e", f: "f", g: "g", h: "h", i: "i") }
      data = { rows: rows }

      serializer.serialize(data)

      GC.start
      GC.disable
      before = GC.stat[:total_allocated_objects]
      10.times { serializer.serialize(data) }
      after = GC.stat[:total_allocated_objects]
      delta = after - before

      expect(delta).to be < 2_000
    ensure
      GC.enable
    end

    it "still computes path correctly for extra: true fields on nested representations" do
      Trane.representation :extras_check do
        field :base, type: :string
        field :extra_val, type: :string, extra: true
      end
      response_def = build_response(200) { field :node, type: :extras_check }
      serializer = described_class.new(response_def, Trane::Registry)

      data = { node: Struct.new(:base, :extra_val, keyword_init: true).new(base: "b", extra_val: "e") }

      expect(serializer.serialize(data)[:node]).to eq(base: "b")
      expect(serializer.serialize(data, extra_attributes: Set["node.extra_val"])[:node]).to eq(base: "b", extra_val: "e")
    end
  end
end
