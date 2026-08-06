# frozen_string_literal: true

namespace :trane do
  desc "Validate Trane contract registry (load files + cross-reference check)"
  task check: :environment do
    if defined?(Trane::BootValidator)
      Trane::Registry.validate!

      if defined?(Trane::RouteValidator)
        Rails.application.reload_routes_unless_loaded
        Trane::RouteValidator.validate!(Rails.application.routes.routes, Trane.registry)
      end

      ops = Trane::Registry.operations.size
      reps = Trane::Registry.representations.size
      errs = Trane::Registry.errors.size
      puts "OK - Trane registry validates clean (#{ops} operations, #{reps} representations, #{errs} errors); " \
           "route/registry cross-check passed."
    else
      puts "Trane::BootValidator not loaded; nothing to check."
    end
  end
end
