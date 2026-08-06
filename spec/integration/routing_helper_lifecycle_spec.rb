# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "contract: keyword integration", type: :integration do
  it "records the operation name in route defaults" do
    route = Rails.application.routes.routes.find do |r|
      r.defaults[:_trane_operation] == "get_user"
    end
    expect(route).not_to be_nil
    expect(route.defaults[:_trane_operation]).to eq("get_user")
  end

  it "all three dummy routes have their operation names in defaults" do
    operation_names = Rails.application.routes.routes
      .map { |r| r.defaults[:_trane_operation] }
      .compact

    expect(operation_names).to include("list_users", "create_user", "get_user")
  end

  it "the operation name reaches the controller on a real GET /users/:id request" do
    get "/dummy-app/api/users/1"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["user"]["id"]).to eq(1)
  end

  it "the operation name reaches the controller on a real GET /users request" do
    get "/dummy-app/api/users"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["users"]).to be_an(Array)
  end

  it "operation names are exposed as named route prefixes" do
    route = Rails.application.routes.routes.find do |r|
      r.name == "list_users"
    end
    expect(route).not_to be_nil
  end
end
