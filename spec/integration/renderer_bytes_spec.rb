# frozen_string_literal: true

# Expected hashes below mirror the dummy-app fixtures.
# Source of truth: trane/spec/integration/dummy/db/seeds.rb and
# the operation definitions under
# trane/spec/integration/dummy/app/api_contract/. If those drift,
# update the expected hashes here in lockstep.

require_relative "integration_helper"

RSpec.describe "Renderer byte output", type: :integration do
  describe "GET /dummy-app/api/users/1" do
    before { get "/dummy-app/api/users/1" }

    it "returns 200" do
      expect(last_response.status).to eq(200)
    end

    it "Content-Type is application/json; charset=utf-8" do
      expect(last_response.headers["Content-Type"]).to eq("application/json; charset=utf-8")
    end

    it "body is exactly JSON.generate of the expected hash" do
      expected = { user: { id: 1, name: "Alice", email: "alice@test.com" } }
      expect(last_response.body).to eq(JSON.generate(expected))
    end
  end

  describe "POST /dummy-app/api/users" do
    before do
      post "/dummy-app/api/users",
           { user: { name: "Charlie", email: "charlie@test.com" } }.to_json,
           "CONTENT_TYPE" => "application/json"
    end

    it "returns 201 with the declared response status" do
      expect(last_response.status).to eq(201)
    end

    it "body is exactly JSON.generate of the expected hash" do
      expected = { user: { id: 3, name: "Charlie", email: "charlie@test.com" } }
      expect(last_response.body).to eq(JSON.generate(expected))
    end
  end

  describe "GET /dummy-app/api/users (list)" do
    before { get "/dummy-app/api/users" }

    it "returns 200" do
      expect(last_response.status).to eq(200)
    end

    it "body parses to the expected JSON structure" do
      parsed = JSON.parse(last_response.body)
      expect(parsed["users"]).to be_an(Array)
      expect(parsed["users"].length).to eq(2)
    end
  end
end
