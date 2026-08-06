# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Registry#errors_by_name" do
  it "equals EMPTY_ERRORS_BY_NAME when no errors are registered" do
    expect(Trane::Registry.errors_by_name).to equal(Trane::Registry::EMPTY_ERRORS_BY_NAME)
    expect(Trane::Registry.errors_by_name).to be_frozen
    expect(Trane::Registry.errors_by_name).to be_empty
  end

  it "indexes a single namespaced error under both FQDN and short-name keys" do
    Trane.errors do
      error "MyApp::Errors::UserNotFound", status_code: 404, description: "Not found"
    end

    index = Trane::Registry.errors_by_name
    defn  = index["MyApp::Errors::UserNotFound"]

    expect(defn).to be_a(Trane::ErrorDefinition)
    expect(index["UserNotFound"]).to equal(defn)
    expect(index.size).to eq(2)
  end

  it "indexes a single top-level error under its FQDN key only" do
    Trane.errors do
      error "UserNotFound", status_code: 404, description: "Not found"
    end

    index = Trane::Registry.errors_by_name

    expect(index.key?("UserNotFound")).to be true
    expect(index.size).to eq(1)
  end

  it "raises Trane::Error with a collision message when two FQDNs share a short name" do
    expect {
      Trane::Registry.replace! do |b|
        b.register_error(Trane::ErrorDefinition.new(key: "MyApp::Errors::UserNotFound", status_code: 404, description: "A"))
        b.register_error(Trane::ErrorDefinition.new(key: "MyApp::Admin::UserNotFound",  status_code: 404, description: "B"))
      end
    }.to raise_error(Trane::Error) do |error|
      expect(error.message).to match(/short-name collision on "UserNotFound"/)
      expect(error.message).to match(/MyApp::Admin::UserNotFound, MyApp::Errors::UserNotFound/)
      expect(error.message).to match(/key :"MyApp::Admin::UserNotFound"/)
    end
  end

  it "preserves the prior snapshot when a collision is detected inside replace!" do
    Trane.errors do
      error "SafeError", status_code: 400, description: "Safe"
    end

    prior_index = Trane::Registry.errors_by_name

    expect {
      Trane::Registry.replace! do |b|
        b.register_error(Trane::ErrorDefinition.new(key: "NsX::Clash", status_code: 409, description: "X"))
        b.register_error(Trane::ErrorDefinition.new(key: "NsY::Clash", status_code: 503, description: "Y"))
      end
    }.to raise_error(Trane::Error)

    expect(Trane::Registry.errors_by_name).to equal(prior_index)
  end

  it "raises on the second CoW register_error when a collision is introduced" do
    Trane.errors do
      error "NsA::Widget", status_code: 404, description: "A"
    end

    snapshot_before = Trane::Registry.errors_by_name

    expect {
      Trane.errors do
        error "NsB::Widget", status_code: 422, description: "B"
      end
    }.to raise_error(Trane::Error, /short-name collision on "Widget"/)

    expect(Trane::Registry.errors_by_name).to equal(snapshot_before)
  end

  it "resolves a namespaced error by both FQDN and short-name to the same definition" do
    Trane.errors do
      error "NsA::Conflict", status_code: 409, description: "Conflict"
    end

    index = Trane::Registry.errors_by_name

    expect(index["NsA::Conflict"]).to equal(index["Conflict"])
    expect(index["NsA::Conflict"]).not_to be_nil
  end
end
