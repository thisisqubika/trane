# frozen_string_literal: true

require "spec_helper"
require "concurrent/array"

RSpec.describe Trane::Docs::Cache do
  let(:fake_definition) do
    { service: { name: "test" }, operations: [], representations: [], errors: [] }
  end

  before do
    described_class.invalidate!
    # Stub Rails.application.routes.routes so Cache.precompute!'s internal
    # `ServiceDefinition.generate(app.routes.routes, service_name: app.name)`
    # does NOT trigger Rails' LazyRouteSet re-drawing. spec_helper resets
    # Configuration before each unit test;
    # if route drawing fires during that window, all dummy routes are
    # re-mounted under /dummy-app/api/... and subsequent integration specs
    # requesting /dummy-app/api/... fail with 404.
    if defined?(Rails) && Rails.application
      routes_double = double("routes_set", routes: [])
      allow(Rails.application).to receive(:routes).and_return(routes_double)
    end
    allow(Trane::Docs::ServiceDefinition).to receive(:generate).and_return(fake_definition)
  end

  describe ".precompute!" do
    it "populates json and html" do
      described_class.precompute!
      expect(described_class.json).to be_a(String)
      expect(described_class.html).to be_a(String)
    end

    it "calls ServiceDefinition.generate only once for both json and html" do
      expect(Trane::Docs::ServiceDefinition).to receive(:generate).once.and_return(fake_definition)
      described_class.precompute!
    end
  end

  describe ".json" do
    it "returns cached value across multiple calls without re-generating" do
      described_class.precompute!
      expect(Trane::Docs::ServiceDefinition).not_to receive(:generate)
      described_class.json
      described_class.json
    end

    it "builds lazily when cold (no precompute! yet)" do
      described_class.invalidate!
      expect(Trane::Docs::ServiceDefinition).to receive(:generate).once.and_return(fake_definition)
      described_class.json
    end
  end

  describe ".html" do
    it "returns cached value across multiple calls" do
      described_class.precompute!
      expect(Trane::Docs::ServiceDefinition).not_to receive(:generate)
      described_class.html
      described_class.html
    end
  end

  describe ".invalidate!" do
    it "clears the cache so next read re-generates" do
      described_class.precompute!
      described_class.invalidate!
      expect(Trane::Docs::ServiceDefinition).to receive(:generate).once.and_return(fake_definition)
      described_class.json
    end
  end

  describe "atomicity" do
    before do
      unless defined?(Rails)
        routes_double = double("routes_set", routes: [])
        app_double = double("app", routes: routes_double)
        stub_const("Rails", double("Rails", application: app_double))
      end
    end

    it "never returns a torn (json, html) pair across precompute! swaps" do
      described_class.invalidate!

      call_count = 0
      allow(Trane::Docs::ServiceDefinition).to receive(:generate) do
        call_count += 1
        probe = "snap-#{call_count}"
        {
          service: { name: probe },
          operations: [],
          representations: [],
          errors: []
        }
      end

      pairs = Concurrent::Array.new
      iterations = 200
      start = Queue.new

      writer = Thread.new do
        start.pop
        iterations.times { described_class.precompute! }
      end

      reader = Thread.new do
        start.pop
        iterations.times do
          json = described_class.json
          html = described_class.html
          pairs << [json, html] if json && html
        end
      end

      2.times { start << :go }
      [writer, reader].each(&:join)

      expect(pairs).not_to be_empty
      torn = pairs.reject do |json, html|
        json_probe = JSON.parse(json).dig("service", "name")
        html.include?(json_probe.to_s)
      end
      expect(torn).to be_empty
    end
  end

  describe "cold-start" do
    before do
      unless defined?(Rails)
        routes_double = double("routes_set", routes: [])
        app_double = double("app", routes: routes_double)
        stub_const("Rails", double("Rails", application: app_double))
      end
    end

    it "calls ServiceDefinition.generate exactly once when reading both json then html cold" do
      described_class.invalidate!
      expect(Trane::Docs::ServiceDefinition).to receive(:generate).once.and_return(fake_definition)

      described_class.json
      described_class.html
    end
  end
end
