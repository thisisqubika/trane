# frozen_string_literal: true

require "spec_helper"
require "trane/routing_extension"

RSpec.describe Trane::RoutingExtension do
  # Simulate the Engine prepending the extension onto a router instance.
  # The stub uses `*args, **kwargs` to mirror Rails' Mapper::Resources#match
  # signature that Trane::RoutingExtension targets.
  let(:base_class) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def match(*args, **kwargs)
        @calls << { args: args, kwargs: kwargs.empty? ? nil : kwargs.dup }
      end
    end
  end

  let(:router) do
    obj = base_class.new
    obj.extend(described_class)
    obj
  end

  def last_call = router.calls.first

  it "passes path and merges operation name into defaults" do
    router.match("/users", to: "users#index", via: :get, contract: { operation: :list_users })

    expect(last_call[:args]).to eq(["/users"])
    expect(last_call[:kwargs][:defaults]).to include(_trane_operation: "list_users")
  end

  it "strips contract: from the kwargs forwarded to super" do
    router.match("/users", to: "users#index", via: :get, contract: { operation: :list_users })

    expect(last_call[:kwargs]).not_to have_key(:contract)
  end

  it "auto-sets as: from the operation name for discoverability in bin/rails routes" do
    router.match("/users", to: "users#index", via: :get, contract: { operation: :list_users })

    expect(last_call[:kwargs][:as]).to eq("list_users")
  end

  it "does not override an explicit Symbol as: already in kwargs" do
    router.match("/users", to: "users#index", via: :get,
                 as: :my_custom_name, contract: { operation: :list_users })

    expect(last_call[:kwargs][:as]).to eq(:my_custom_name)
  end

  it "does not override an explicit String as: already in kwargs" do
    router.match("/users", to: "users#index", via: :get,
                 as: "my_string_name", contract: { operation: :list_users })

    expect(last_call[:kwargs][:as]).to eq("my_string_name")
  end

  it "replaces a truthy non-String/Symbol as: (Rails DEFAULT sentinel) with operation name" do
    router.match("/users", to: "users#index", via: :get,
                 as: Object.new, contract: { operation: :list_users })

    expect(last_call[:kwargs][:as]).to eq("list_users")
  end

  it "preserves existing defaults entries" do
    router.match("/users/:id", to: "users#show", via: :get,
                 defaults: { format: :json }, contract: { operation: :get_user })

    expect(last_call[:kwargs][:defaults]).to include(format: :json, _trane_operation: "get_user")
  end

  it "passes through additional kwargs unchanged" do
    router.match("/users", to: "users#index", via: :get,
                 constraints: { subdomain: "api" }, contract: { operation: :list_users })

    expect(last_call[:kwargs][:constraints]).to eq(subdomain: "api")
  end

  it "coerces operation name to string in defaults" do
    router.match("/users/:id", to: "users#destroy", via: :delete,
                 contract: { operation: :destroy_user })

    expect(last_call[:kwargs][:defaults][:_trane_operation]).to eq("destroy_user")
  end

  it "forwards routes without contract: unchanged (no defaults injected)" do
    router.match("/up", to: "rails/health#show", via: :get)

    expect(last_call[:args]).to eq(["/up"])
    expect(last_call[:kwargs]).not_to have_key(:defaults)
    expect(last_call[:kwargs]).not_to have_key(:contract)
  end

  it "handles zero-positional-arg calls (hash-shorthand routes) without error" do
    router.match(to: "rails/health#show", via: :get)

    expect(last_call[:args]).to eq([])
  end

  # Rails 7.x / 8.0 positional-hash calling convention:
  # map_method calls match(*path_args, options_hash) — the options hash is a
  # plain positional argument, not keyword arguments. Ruby 3.x does not
  # auto-convert positional hashes to kwargs, so we must detect and handle
  # this form explicitly.
  context "Rails 7.x positional-hash calling convention" do
    it "injects _trane_operation into the positional options hash" do
      router.match("/users", { to: "users#index", via: :get, contract: { operation: :list_users } })

      expect(last_call[:args]).to eq(["/users", { to: "users#index", via: :get,
                                                   defaults: { _trane_operation: "list_users" },
                                                   as: "list_users" }])
    end

    it "strips contract: from the positional options hash forwarded to super" do
      router.match("/users", { to: "users#index", via: :get, contract: { operation: :list_users } })

      forwarded_options = last_call[:args].last
      expect(forwarded_options).not_to have_key(:contract)
    end

    it "preserves existing defaults in the positional options hash" do
      router.match("/users/:id", { to: "users#show", via: :get,
                                   defaults: { format: :json },
                                   contract: { operation: :get_user } })

      expect(last_call[:args].last[:defaults]).to include(format: :json, _trane_operation: "get_user")
    end

    it "does not override an explicit :as in the positional options hash" do
      router.match("/users", { to: "users#index", via: :get,
                               as: :my_name,
                               contract: { operation: :list_users } })

      expect(last_call[:args].last[:as]).to eq(:my_name)
    end

    it "passes through without modification when no contract: key present" do
      router.match("/up", { to: "rails/health#show", via: :get })

      expect(last_call[:args]).to eq(["/up", { to: "rails/health#show", via: :get }])
    end
  end

  describe "contract: hash validation (fail-loud on typos)" do
    it "exposes CONTRACT_KEYS as the single source of truth for valid contract: keys" do
      expect(Trane::RoutingExtension::CONTRACT_KEYS).to eq(%i[operation])
    end

    it "raises when contract: is an empty Hash" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: {})
      }.to raise_error(Trane::RoutingContractError, /requires a non-empty :operation/)
    end

    it "raises when contract: { operation: nil }" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { operation: nil })
      }.to raise_error(Trane::RoutingContractError, /requires a non-empty :operation/)
    end

    it "raises when contract: { operation: \"\" }" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { operation: "" })
      }.to raise_error(Trane::RoutingContractError, /requires a non-empty :operation/)
    end

    it "raises when contract: { operation: \"   \" } (whitespace only)" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { operation: "   " })
      }.to raise_error(Trane::RoutingContractError, /requires a non-empty :operation/)
    end

    it "raises with an exact Did-you-mean message for a misspelled key" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { operaton: :list_users })
      }.to raise_error(Trane::RoutingContractError, "Unknown key `operaton` in contract:. Did you mean `operation`?")
    end

    it "raises without a Did-you-mean suggestion when no candidate is close" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { xyz: :list_users })
      }.to raise_error(Trane::RoutingContractError) do |error|
        expect(error.message).to include("Unknown key `xyz` in contract:.")
        expect(error.message).not_to include("Did you mean")
      end
    end

    it "raises for the Rails 7.x positional-hash calling convention too" do
      expect {
        router.match("/u", { to: "users#index", via: :get, contract: { operaton: :x } })
      }.to raise_error(Trane::RoutingContractError, /Did you mean `operation`\?/)
    end

    it "does not raise for a valid contract: { operation: :name } (regression)" do
      expect {
        router.match("/users", to: "users#index", via: :get, contract: { operation: :list_users })
      }.not_to raise_error
    end
  end
end
