# frozen_string_literal: true

require "json"

module Trane
  module Docs
    # Memoized JSON + HTML output of the ServiceDefinition. The pair lives
    # inside a single frozen Snapshot ivar built atomically by
    # `precompute!`: every Snapshot instance carries a `(json, html)`
    # pair derived from one ServiceDefinition.generate call, so no
    # caller can observe a torn pair WITHIN a single snapshot
    # generation. The previous design wrote `@json` and `@html` in
    # sequence, leaving a window where a reader saw new JSON paired
    # with old HTML across a Rails reload.
    #
    # Consistency is per-snapshot-instance, not per-call-pair: a thread
    # that reads `Cache.json` then `Cache.html` may observe two
    # different snapshots if `precompute!` runs between the two calls.
    # In production this is unobservable (each Rack request hits ONE of
    # `/docs.json` or `/docs`, never both), and cross-request
    # ordering across reloads is out of scope for this module.
    #
    # `precompute!` is ALWAYS lazy — triggered by the first `json`/`html`
    # read via `ensure_snapshot`. Trane::Engine's `to_prepare` block calls
    # `invalidate!` (not `precompute!`): during `to_prepare` the host routes
    # are not drawn yet (it runs before the Finisher's
    # set_routes_reloader_hook, in every environment), so precomputing there
    # would build a snapshot from an empty route set and every operation would
    # fall back to method "GET" with an empty path. Deferring to the first
    # post-boot read — inside a request, with the routes drawn — is what makes
    # the docs report each operation's real HTTP verb and path. Concurrent
    # cold readers may both build a snapshot; one assignment wins, the other is
    # GC'd — wasted work, never inconsistent state.
    module Cache
      Snapshot = Data.define(:json, :html)

      class << self
        def json
          ensure_snapshot
          @snapshot&.json
        end

        def html
          ensure_snapshot
          @snapshot&.html
        end

        # Build a fresh (json, html) Snapshot from the current
        # ServiceDefinition and swap it in atomically.
        #
        # @return [void]
        def precompute!
          # The only Rails read in the docs layer: the service name is
          # Rails.application.name, never Trane configuration.
          app = Rails.application
          definition = ServiceDefinition.generate(app.routes.routes, service_name: app.name)
          @snapshot = Snapshot.new(
            json: JSON.generate(definition),
            html: HtmlRenderer.render(definition)
          )
          nil
        end

        def invalidate!
          @snapshot = nil
        end

        private

        def ensure_snapshot
          precompute! if @snapshot.nil?
        end
      end
    end
  end
end
