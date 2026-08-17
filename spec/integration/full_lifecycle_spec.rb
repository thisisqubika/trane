# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Full lifecycle", type: :integration do
  describe "GET /dummy-app/api/users" do
    it "returns serialized list of users" do
      get "/dummy-app/api/users"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)

      expect(body["users"]).to be_an(Array)
      expect(body["users"].length).to eq(2)
      expect(body["users"][0]["name"]).to eq("Alice")
      expect(body["users"][0]["email"]).to eq("alice@test.com")
      expect(body["users"][0]).not_to have_key("nickname") # extra field excluded
    end
  end

  describe "GET /dummy-app/api/users/:id" do
    it "returns a single serialized user" do
      get "/dummy-app/api/users/1"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)

      expect(body["user"]["id"]).to eq(1)
      expect(body["user"]["name"]).to eq("Alice")
      expect(body["user"]["email"]).to eq("alice@test.com")
    end

    it "excludes extra fields by default" do
      get "/dummy-app/api/users/1"

      body = JSON.parse(last_response.body)
      expect(body["user"]).not_to have_key("nickname")
    end
  end

  describe "POST /dummy-app/api/users" do
    it "returns created user with 201 status" do
      post "/dummy-app/api/users", { user: { name: "Charlie", email: "charlie@test.com" } }.to_json,
           "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)

      expect(body["user"]["id"]).to eq(3)
      expect(body["user"]["name"]).to eq("Charlie")
    end
  end
end
