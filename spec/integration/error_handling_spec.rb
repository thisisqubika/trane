# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Error handling", type: :integration do
  describe "registered error" do
    it "returns structured error JSON with correct status" do
      get "/dummy-app/api/users/999"

      expect(last_response.status).to eq(404)
      body = JSON.parse(last_response.body)

      expect(body["errors"]).to be_an(Array)
      expect(body["errors"].length).to eq(1)
      expect(body["errors"][0]["key"]).to eq("UserNotFound")
      expect(body["errors"][0]["message"]).to eq("User not found")
    end
  end

  describe "registered error with custom message" do
    it "returns error with the exception message" do
      post "/dummy-app/api/users", {}.to_json, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)

      expect(body["errors"][0]["key"]).to eq("UserInvalid")
      expect(body["errors"][0]["message"]).to eq("Name can't be blank")
    end
  end
end
