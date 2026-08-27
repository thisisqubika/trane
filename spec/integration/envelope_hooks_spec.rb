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
end
