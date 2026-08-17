# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Extra attributes", type: :integration do
  it "includes extra fields when requested via query params" do
    get "/dummy-app/api/users/1?extra_attributes[]=user.nickname"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)

    expect(body["user"]["nickname"]).to eq("Ali")
  end

  it "excludes extra fields when not requested" do
    get "/dummy-app/api/users/1"

    body = JSON.parse(last_response.body)
    expect(body["user"]).not_to have_key("nickname")
  end

  it "includes extra fields in array responses when requested" do
    get "/dummy-app/api/users?extra_attributes[]=users.nickname"

    body = JSON.parse(last_response.body)
    expect(body["users"][0]["nickname"]).to eq("Ali")
    expect(body["users"][1]["nickname"]).to eq("Bobby")
  end
end
