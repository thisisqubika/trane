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
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*", "LICENSE.txt"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties",      ">= 7.2", "< 9"
  spec.add_dependency "activesupport", ">= 7.2", "< 9"
  spec.add_dependency "actionpack",    ">= 7.2", "< 9"
end
