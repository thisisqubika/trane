# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Configurable envelopes", type: :integration do
  # integration_helper re-applies the dummy initializer and freezes the configuration in a
  # before(:each), so reconfiguring has to go through the helper built for it.
  def with_success_envelope
    Trane::Testing.with_configuration(
      strict_mode: :ignore,
      success_envelope: ->(body) { { status: "success" }.merge(body) }
    ) { yield }
  end

  it "wraps a successful response" do
    with_success_envelope do
      get "/dummy-app/api/users/1"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["status"]).to eq("success")
    end
  end

  # The key order is part of what is being pinned, so this asserts the raw bytes.
  it "puts the envelope's key first" do
    with_success_envelope do
      get "/dummy-app/api/users/1"

      expect(last_response.body).to start_with('{"status":"success",')
    end
  end

  # A method and not a constant: rubocop-rspec's LeakyConstantDeclaration rejects a constant
  # declared inside an example group, and this repo runs that plugin.
  def error_envelope
    lambda do |exception, definition|
      { status: "error",
        messages: [ { level: "error",
                      key: definition ? definition.key.to_s : exception.class.name,
                      dsc: exception.message } ] }
    end
  end

  def with_error_envelope
    Trane::Testing.with_configuration(strict_mode: :ignore, error_envelope: error_envelope) { yield }
  end

  it "wraps a registered error and keeps the definition's status" do
    with_error_envelope do
      get "/dummy-app/api/users/999"

      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body))
        .to eq({ "status" => "error",
                 "messages" => [ { "level" => "error", "key" => "UserNotFound",
                                   "dsc" => "User not found" } ] })
    end
  end

  it "wraps an unhandled error with its class name and raw message" do
    with_error_envelope do
      get "/dummy-app/api/boom"

      expect(last_response.status).to eq(500)
      expect(JSON.parse(last_response.body)["messages"].first)
        .to eq({ "level" => "error", "key" => "ArgumentError", "dsc" => "raw detail" })
    end
  end

  it "leaves the default shape alone when no envelope is configured" do
    get "/dummy-app/api/users/999"

    expect(JSON.parse(last_response.body)["errors"].first["key"]).to eq("UserNotFound")
  end
end
