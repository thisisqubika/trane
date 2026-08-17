# frozen_string_literal: true

RSpec.describe Trane::Docs::ServiceDefinition do
  before do
    Trane.representation :user do
      field :id, type: :integer
      field :name, type: :string
      field :birthday, type: :date, format: :iso8601
      field :nickname, type: :string, extra: true
    end

    Trane.errors do
      error :UserNotFound, status_code: 404, description: "User not found"
    end

    Trane.operation :get_user do
      summary "Get a user by id"

      request do
        path :id, type: :integer
      end

      response 200 do
        field :user, type: :user
      end

      errors do
        key :UserNotFound
      end
    end

    Trane.operation :list_users do
      summary "List all users"

      response 200 do
        field :users, type: :array, of: :user
      end
    end

    Trane.operation :create_user do
      summary "Create a user"

      request do
        body do
          field :user, required: true do
            field :name, type: :string, required: true
            field :email, type: :string
          end
        end
      end

      response 201 do
        field :user, type: :user
      end
    end
  end

  # Mock route objects for testing
  let(:mock_routes) do
    [
      mock_route("GET", "/users/:id", "get_user"),
      mock_route("GET", "/users", "list_users"),
      mock_route("POST", "/users", "create_user")
    ]
  end

  def mock_route(method, path, operation)
    path_spec = double("path_spec", to_s: "#{path}(.:format)")
    path_obj = double("path", spec: path_spec)
    double("route",
           defaults: { _trane_operation: operation },
           verb: method,
           path: path_obj)
  end

  describe ".generate" do
    subject(:definition) { described_class.generate(mock_routes, service_name: "testapi") }

    it "includes service metadata" do
      expect(definition[:service]).to eq({ name: "testapi" })
    end

    it "includes all operations" do
      ops = definition[:operations]
      expect(ops.map { |o| o[:id] }).to contain_exactly("get_user", "list_users", "create_user")
    end

    it "includes operation details" do
      op = definition[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:summary]).to eq("Get a user by id")
      expect(op[:method]).to eq("GET")
      expect(op[:path]).to eq("/users/:id")
    end

    it "includes request params" do
      op = definition[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:request][:params]).to eq([
        { name: "id", type: "integer", location: "path", required: true }
      ])
    end

    it "includes request body fields" do
      op = definition[:operations].find { |o| o[:id] == "create_user" }
      expect(op[:request][:body].length).to eq(1)
      expect(op[:request][:body][0][:name]).to eq("user")
      expect(op[:request][:body][0][:children].length).to eq(2)
    end

    it "includes response fields" do
      op = definition[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:responses].length).to eq(1)
      expect(op[:responses][0][:status]).to eq(200)
      expect(op[:responses][0][:fields][0][:name]).to eq("user")
    end

    it "includes error keys on operations" do
      op = definition[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:errors]).to eq([ "UserNotFound" ])
    end

    it "includes all representations" do
      reps = definition[:representations]
      expect(reps.length).to eq(1)
      expect(reps[0][:name]).to eq("user")
      expect(reps[0][:fields].map { |f| f[:name] }).to eq(%w[id name birthday nickname])
    end

    it "includes field metadata in representations" do
      user_rep = definition[:representations][0]
      birthday = user_rep[:fields].find { |f| f[:name] == "birthday" }
      expect(birthday[:format]).to eq("iso8601")

      nickname = user_rep[:fields].find { |f| f[:name] == "nickname" }
      expect(nickname[:extra]).to be true
    end

    it "includes all errors" do
      errs = definition[:errors]
      expect(errs.length).to eq(1)
      expect(errs[0]).to eq({ key: "UserNotFound", status_code: 404, description: "User not found" })
    end

    it "includes array type info" do
      op = definition[:operations].find { |o| o[:id] == "list_users" }
      field = op[:responses][0][:fields][0]
      expect(field[:name]).to eq("users")
      expect(field[:type]).to eq("array")
      expect(field[:array_of]).to eq("user")
    end

    it "emits required: true for body fields declared required" do
      op = definition[:operations].find { |o| o[:id] == "create_user" }
      user_field = op[:request][:body][0]
      expect(user_field[:required]).to be true
      name_field = user_field[:children].find { |f| f[:name] == "name" }
      expect(name_field[:required]).to be true
    end

    it "emits required: false for body fields not declared required" do
      op = definition[:operations].find { |o| o[:id] == "create_user" }
      user_field = op[:request][:body][0]
      email_field = user_field[:children].find { |f| f[:name] == "email" }
      expect(email_field[:required]).to be false
    end

    it "does not include required key for response fields" do
      op = definition[:operations].find { |o| o[:id] == "get_user" }
      response_field = op[:responses][0][:fields][0]
      expect(response_field).not_to have_key(:required)
    end

    it "does not include required key for representation fields" do
      user_rep = definition[:representations][0]
      user_rep[:fields].each do |f|
        expect(f).not_to have_key(:required)
      end
    end

    context "FQDN error keys" do
      before do
        Trane.errors do
          error "Namespaced::PaymentFailed", status_code: 402, description: "Payment failed"
        end
      end

      it "emits the FQDN key as-is in the errors list" do
        defn = described_class.generate(mock_routes, service_name: "testapi")
        fqdn_err = defn[:errors].find { |e| e[:key] == "Namespaced::PaymentFailed" }
        expect(fqdn_err).not_to be_nil
        expect(fqdn_err[:status_code]).to eq(402)
      end
    end

    context "enum: support" do
      subject(:extended_definition) { described_class.generate(extended_routes, service_name: "testapi") }

      before do
        Trane.representation :product do
          field :status, type: :string, enum: [ "active", "archived" ]
        end

        Trane.operation :list_products do
          summary "List products"

          request do
            query :sort, type: :string, enum: [ "asc", "desc" ]
          end

          response 200 do
            field :products, of: :product
          end
        end
      end

      let(:extended_routes) do
        mock_routes + [ mock_route("GET", "/products", "list_products") ]
      end


      it "emits enum for representation fields" do
        product_rep = extended_definition[:representations].find { |r| r[:name] == "product" }
        status_field = product_rep[:fields].find { |f| f[:name] == "status" }
        expect(status_field[:enum]).to eq([ "active", "archived" ])
      end

      it "does not emit enum key for fields without enum" do
        user_rep = extended_definition[:representations].find { |r| r[:name] == "user" }
        id_field = user_rep[:fields].find { |f| f[:name] == "id" }
        expect(id_field).not_to have_key(:enum)
      end

      it "emits enum for query params" do
        op = extended_definition[:operations].find { |o| o[:id] == "list_products" }
        sort_param = op[:request][:params].find { |p| p[:name] == "sort" }
        expect(sort_param[:enum]).to eq([ "asc", "desc" ])
      end

      it "serializes Date enum values to ISO 8601 strings" do
        Trane.representation :dated_item do
          field :expiry, type: :date, enum: [ Date.new(2026, 1, 1) ]
        end
        Trane.operation :list_dated_items do
          response 200 do
            field :items, of: :dated_item
          end
        end
        defn = described_class.generate(mock_routes + [ mock_route("GET", "/dated_items", "list_dated_items") ], service_name: "testapi")
        dated_rep = defn[:representations].find { |r| r[:name] == "dated_item" }
        expiry_field = dated_rep[:fields].find { |f| f[:name] == "expiry" }
        expect(expiry_field[:enum]).to eq([ "2026-01-01" ])
      end
    end
  end

  describe "verb extraction" do
    before do
      Trane.operation :update_user do
        summary "Update a user"
        response 200 do
          field :user, type: :user
        end
      end
    end

    it "returns the verb string when route.verb is a String" do
      routes = [ mock_route("GET", "/users/:id", "get_user") ]
      op = described_class.generate(routes, service_name: "testapi")[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:method]).to eq("GET")
    end

    # The two multi-verb cases below document extract_method's defensive
    # fallback. In practice RouteValidator rejects multi-verb contract routes
    # before they reach the docs, so these inputs cannot occur at runtime.
    it "returns the first verb when route.verb is a multi-verb String (Rails 8: was 'PATCH|PUT')" do
      routes = [ mock_route("PATCH|PUT", "/users/:id", "update_user") ]
      op = described_class.generate(routes, service_name: "testapi")[:operations].find { |o| o[:id] == "update_user" }
      expect(op[:method]).to eq("PATCH")
    end

    it "returns the verb when route.verb is a single-verb Regexp" do
      routes = [ mock_route(/^GET$/, "/users/:id", "get_user") ]
      op = described_class.generate(routes, service_name: "testapi")[:operations].find { |o| o[:id] == "get_user" }
      expect(op[:method]).to eq("GET")
    end

    it "returns the first verb when route.verb is a multi-verb Regexp (regression: was 'PATCHPUT')" do
      routes = [ mock_route(/^PATCH|PUT$/, "/users/:id", "update_user") ]
      op = described_class.generate(routes, service_name: "testapi")[:operations].find { |o| o[:id] == "update_user" }
      expect(op[:method]).to eq("PATCH")
    end
  end
end
