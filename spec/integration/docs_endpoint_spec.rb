# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Documentation endpoints", type: :integration do
  describe "GET /dummy-app/docs.json" do
    it "returns JSON service definition" do
      get "/dummy-app/docs.json"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("application/json")

      body = JSON.parse(last_response.body)

      expect(body["service"]["name"]).to eq("dummy-app")
    end

    it "includes all operations" do
      get "/dummy-app/docs.json"
      body = JSON.parse(last_response.body)

      op_ids = body["operations"].map { |o| o["id"] }
      expect(op_ids).to include("list_users", "get_user", "create_user")
    end

    it "includes representations" do
      get "/dummy-app/docs.json"
      body = JSON.parse(last_response.body)

      rep_names = body["representations"].map { |r| r["name"] }
      expect(rep_names).to include("user")
    end

    it "includes errors" do
      get "/dummy-app/docs.json"
      body = JSON.parse(last_response.body)

      error_keys = body["errors"].map { |e| e["key"] }
      expect(error_keys).to include("UserNotFound", "UserInvalid")
    end
  end

  describe "GET /dummy-app/docs" do
    it "returns HTML documentation" do
      get "/dummy-app/docs"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
      expect(last_response.body).to include("<!DOCTYPE html>")
    end

    it "includes operation names in the HTML" do
      get "/dummy-app/docs"

      expect(last_response.body).to include("get_user")
      expect(last_response.body).to include("list_users")
    end

    it "includes sidebar navigation" do
      get "/dummy-app/docs"

      expect(last_response.body).to include('class="sidebar"')
    end

    it "includes representation sections" do
      get "/dummy-app/docs"

      expect(last_response.body).to include('id="rep-user"')
    end
  end

  context "with caching" do
    it "does not regenerate ServiceDefinition on cached requests" do
      get "/dummy-app/docs.json"

      expect(Trane::Docs::ServiceDefinition).not_to receive(:generate)
      get "/dummy-app/docs.json"
    end
  end

  context "unit-level Docs::App#call" do
    let(:docs_app) { Trane::Docs::App.new }

    def rack_env(path)
      {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO"      => path,
        "rack.input"     => StringIO.new
      }
    end

    it "serves JSON when PATH_INFO ends with .json" do
      status, headers, body = docs_app.call(rack_env("/dummy-app/docs.json"))

      expect(status).to eq(200)
      expect(headers["content-type"]).to include("application/json")
      parsed = JSON.parse(body.first)
      expect(parsed).to have_key("service")
    end

    it "serves HTML when PATH_INFO does not end with .json" do
      status, headers, body = docs_app.call(rack_env("/dummy-app/docs"))

      expect(status).to eq(200)
      expect(headers["content-type"]).to include("text/html")
      expect(body.first).to include("<!DOCTYPE html>")
    end
  end
end
