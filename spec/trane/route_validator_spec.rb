# frozen_string_literal: true

RSpec.describe Trane::RouteValidator do
  # Builds a fake route object shaped like an ActionDispatch::Journey::Route:
  # responds to #verb, #defaults, and #path (which itself responds to #spec).
  # Uses anonymous Structs so no constant leaks into the top-level namespace.
  def build_route(verb: "GET", path: "/x", trane_operation: nil)
    defaults = trane_operation.nil? ? {} : { _trane_operation: trane_operation }
    path_double = Struct.new(:spec).new(path)
    Struct.new(:verb, :defaults, :path).new(verb, defaults, path_double)
  end

  describe ".validate!" do
    context "when the route's operation is registered (String vs Symbol comparison)" do
      before do
        Trane.operation :get_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "does not raise" do
        routes = [build_route(path: "/users/:id", trane_operation: "get_user")]

        expect { described_class.validate!(routes, Trane::Registry) }.not_to raise_error
      end
    end

    context "when the route's operation is not registered" do
      before do
        Trane.operation :get_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "raises naming the verb, path, missing operation, and a Did-you-mean suggestion" do
        routes = [build_route(verb: "GET", path: "/users/:id(.:format)", trane_operation: "get_usr")]

        expect { described_class.validate!(routes, Trane::Registry) }
          .to raise_error(Trane::RoutingContractError) do |error|
            expect(error.message).to include("GET /users/:id(.:format)")
            expect(error.message).to include("get_usr")
            expect(error.message).to include("get_user")
          end
      end
    end

    context "when route defaults have no _trane_operation" do
      it "skips routes with a nil operation" do
        routes = [build_route(trane_operation: nil)]

        expect { described_class.validate!(routes, Trane::Registry) }.not_to raise_error
      end

      it "skips routes with a blank string operation" do
        routes = [build_route(trane_operation: "")]

        expect { described_class.validate!(routes, Trane::Registry) }.not_to raise_error
      end
    end

    context "with multiple orphaned operations" do
      before do
        Trane.operation :get_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "names every orphan in a single raised message" do
        routes = [
          build_route(verb: "GET", path: "/users/:id", trane_operation: "get_usr"),
          build_route(verb: "POST", path: "/widgets", trane_operation: "create_widgt")
        ]

        expect { described_class.validate!(routes, Trane::Registry) }
          .to raise_error(Trane::RoutingContractError) do |error|
            expect(error.message).to include("get_usr")
            expect(error.message).to include("create_widgt")
          end
      end
    end

    context "when the same orphaned operation appears on multiple route rows" do
      it "reports it only once (e.g. Rails' auto-added HEAD row sharing GET's defaults)" do
        routes = [
          build_route(verb: "GET", path: "/users/:id", trane_operation: "get_usr"),
          build_route(verb: "HEAD", path: "/users/:id", trane_operation: "get_usr")
        ]

        expect { described_class.validate!(routes, Trane::Registry) }
          .to raise_error(Trane::RoutingContractError) do |error|
            expect(error.message.scan("get_usr").size).to eq(1)
          end
      end
    end

    context "with an empty routes collection" do
      it "does not raise" do
        expect { described_class.validate!([], Trane::Registry) }.not_to raise_error
      end
    end

    context "with an empty registry" do
      it "does not raise when no route declares an operation" do
        routes = [build_route(trane_operation: nil)]

        expect { described_class.validate!(routes, Trane::Registry) }.not_to raise_error
      end
    end

    context "when a route with a contract maps to multiple HTTP verbs" do
      before do
        Trane.operation :update_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "raises naming the collapsed verb, the path and the operation" do
        routes = [build_route(verb: "PATCH|PUT", path: "/users/:id(.:format)", trane_operation: "update_user")]

        expect { described_class.validate!(routes, Trane::Registry) }
          .to raise_error(Trane::RoutingContractError) do |error|
            expect(error.message).to include("PATCH|PUT /users/:id(.:format)")
            expect(error.message).to include("update_user")
            expect(error.message).to include("exactly one HTTP verb")
          end
      end
    end

    context "when a route with a contract accepts any HTTP verb (blank verb)" do
      before do
        Trane.operation :update_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "raises, reporting the route as ANY" do
        routes = [build_route(verb: "", path: "/users/:id", trane_operation: "update_user")]

        expect { described_class.validate!(routes, Trane::Registry) }
          .to raise_error(Trane::RoutingContractError) do |error|
            expect(error.message).to include("ANY /users/:id")
          end
      end
    end

    context "when a route with a contract maps to a single verb" do
      before do
        Trane.operation :update_user do
          response 200 do
            field :id, type: :integer
          end
        end
      end

      it "does not raise" do
        routes = [build_route(verb: "PATCH", path: "/users/:id", trane_operation: "update_user")]

        expect { described_class.validate!(routes, Trane::Registry) }.not_to raise_error
      end
    end
  end
end
