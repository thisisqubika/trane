# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Trane Engine prepends Trane::RoutingExtension onto ActionDispatch::Routing::Mapper",
               type: :integration do
  it "prepends Trane::RoutingExtension into Mapper ancestors" do
    expect(ActionDispatch::Routing::Mapper.ancestors)
      .to include(Trane::RoutingExtension)
  end

  it "RoutingExtension precedes Mapper::Resources in the ancestor chain" do
    ancestors = ActionDispatch::Routing::Mapper.ancestors
    ext_idx = ancestors.index(Trane::RoutingExtension)
    res_idx = ancestors.index(ActionDispatch::Routing::Mapper::Resources)
    expect(ext_idx).to be < res_idx
  end

  it "makes the contract: keyword functional in any routes.draw block" do
    operation_names = Rails.application.routes.routes
      .map { |r| r.defaults[:_trane_operation] }
      .compact
    expect(operation_names).to include("list_users", "get_user", "create_user")
  end

  it "routes without contract: do not get :_trane_operation in defaults" do
    route = Rails.application.routes.routes.find { |r| r.path.spec.to_s.include?("dummy-app/docs") }
    expect(route&.defaults).not_to have_key(:_trane_operation)
  end
end
