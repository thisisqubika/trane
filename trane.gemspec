# frozen_string_literal: true

require_relative "lib/trane/version"

Gem::Specification.new do |spec|
  spec.name          = "trane"
  spec.version       = Trane::VERSION
  spec.authors       = [ "Ignacio Jorge", "Juan Papazian", "Jose Bauzan", "Tomas Gallardo", "Gaston Gabadian" ]
  spec.email         = [ "ignacio.jorge@qubika.com", "juan.papazian@qubika.com", "jose.bauzan@qubika.com", "tomas.gallardo@qubika.com", "gaston.gabadian@qubika.com" ]

  spec.summary       = "Contract enforcement and documentation layer for Rails APIs."
  spec.description   = "Trane enforces structured JSON responses, provides deterministic " \
                        "serialization via contract-based representations, captures errors globally, " \
                        "and publishes API documentation (HTML + JSON)."
  spec.license       = "MIT"
  spec.homepage      = "https://github.com/thisisqubika/trane"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "source_code_uri"       => "https://github.com/thisisqubika/trane",
    "changelog_uri"         => "https://github.com/thisisqubika/trane/blob/main/CHANGELOG.md",
    "bug_tracker_uri"       => "https://github.com/thisisqubika/trane/issues",
    "documentation_uri"     => "https://github.com/thisisqubika/trane/tree/main/docs/wiki",
    "rubygems_mfa_required" => "true"
  }

  # config/ carries the Engine's routes, which Rails loads by path at mount time.
  # Without it the published gem mounts an Engine with no routes and the
  # documentation endpoints answer 404 — see spec/trane/packaging_spec.rb.
  spec.files = Dir["lib/**/*", "config/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties",      ">= 7.2", "< 9"
  spec.add_dependency "activesupport", ">= 7.2", "< 9"
  spec.add_dependency "actionpack",    ">= 7.2", "< 9"
  spec.add_dependency "rack",          ">= 2.2.4", "< 4"
end
