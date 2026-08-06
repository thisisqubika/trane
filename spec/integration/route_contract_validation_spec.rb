# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Route/registry contract cross-check", type: :integration do
  describe "Validation B — RouteValidator against real Rails routes" do
    it "does not raise for the dummy app's real route set and registry (happy path)" do
      expect {
        Trane::RouteValidator.validate!(Rails.application.routes.routes, Trane.registry)
      }.not_to raise_error
    end

    it "raises naming the real route when its operation vanishes from the registry" do
      ops  = Trane.registry.operations.dup
      reps = Trane.registry.representations.dup
      errs = Trane.registry.errors.dup
      ops.delete(:get_user)

      Trane::Registry.replace! do |builder|
        reps.each_value { |definition| builder.register_representation(definition) }
        errs.each_value { |definition| builder.register_error(definition) }
        ops.each_value { |definition| builder.register_operation(definition) }
      end

      expect {
        Trane::RouteValidator.validate!(Rails.application.routes.routes, Trane.registry)
      }.to raise_error(Trane::RoutingContractError) do |error|
        expect(error.message).to include("/dummy-app/api/users/:id")
        expect(error.message).to include("get_user")
      end
    end
  end

  describe "Validation A — contract: hash validation via a real (throwaway) RouteSet" do
    it "raises for an unknown contract: key without corrupting the shared application route set" do
      throwaway = ActionDispatch::Routing::RouteSet.new

      expect {
        throwaway.draw { get "/x", to: "test#index", contract: { operaton: :y } }
      }.to raise_error(Trane::RoutingContractError, /Did you mean `operation`\?/)
    end
  end
end
