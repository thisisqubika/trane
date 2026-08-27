# frozen_string_literal: true

require "active_support/concern"

module Trane
  module Controller
    # Mixin that captures StandardError subclasses and maps them to
    # registered Trane errors. Resolves the exception class via the
    # precomputed errors_by_name index on the Registry snapshot —
    # single lookup on FQDN match, with a short-name fallback (via
    # String#rpartition) for hosts that registered errors by short
    # name. Include in your API base controller. Does NOT add
    # `render contract:` support — combine with Trane::Controller::Renderer
    # or use the composer Trane::Controller.
    #
    # WARNING: this installs rescue_from StandardError at the class
    # level. Including in a base controller that also serves HTML
    # would catch errors Devise / Pundit / etc. expect to bubble up.
    # Recommended: include only in API base controllers.
    #
    # Rails-reserved exceptions (those in
    # ActionDispatch::ExceptionWrapper.rescue_responses, e.g.
    # ActiveRecord::RecordNotFound → 404, ActionController::ParameterMissing → 400)
    # are re-raised when no Trane error is registered for them, so Rails'
    # exception middleware applies its default status mapping. Hosts that
    # want to swallow these into the Trane envelope can register them
    # explicitly via `Trane.errors { error "ActiveRecord::RecordNotFound", ... }`;
    # the Trane lookup wins over the re-raise path. Alternatively, setting
    # `Trane.configuration.rescue_rails_reserved = true` swallows every
    # reserved exception without registering each one by hand — useful for an
    # API that must answer JSON on every path (default: false).
    #
    # SECURITY NOTE: a registered error's envelope carries the exception's
    # runtime #message, in EVERY environment including production. Framework
    # and library exception messages are written for logs and may reveal
    # internals (model names, query conditions). Prefer the recommended
    # pattern (docs/wiki/Error-Handling.md) — rescue the framework exception
    # and raise a domain error with a curated message — and register framework
    # exceptions directly only when their messages are acceptable to expose.
    #
    # PRODUCTION NOTE: re-raised exceptions surface via Rails' default
    # middleware. Keep `config.consider_all_requests_local = false` in
    # production so `ActionDispatch::ShowExceptions` serves the static
    # `public/404.html` / `500.html` pages. With `consider_all_requests_local`
    # enabled in production, `ActionDispatch::DebugExceptions` would expose
    # the exception class + message + backtrace.
    module ErrorHandler
      extend ActiveSupport::Concern

      included do
        rescue_from StandardError, with: :_trane_handle_error
      end

      # Returns the frozen Set of Rails-reserved exception class NAMES
      # (Strings) derived from ActionDispatch::ExceptionWrapper.rescue_responses.
      # Memoized on first call (after Rails boot completes). Returns an empty
      # Set when Rails is not loaded.
      #
      # Names, not Class objects, on purpose: memoizing classes would pin
      # host-registered (Zeitwerk-reloadable) exception constants in the gem
      # forever, and after a development reload the stale Class would no
      # longer match its reloaded replacement. Names survive reloads.
      #
      # NOTE: callers MUST invoke this post-boot. The Rails Engine initializers
      # merge AR/AC entries into `rescue_responses` during boot; calling this
      # earlier would memoize an incomplete list. In practice the first error
      # arrives in a request thread, which is always post-boot — but tests or
      # explicit pre-boot invocations would have to reset @rails_reserved_names
      # afterwards.
      def self.rails_reserved_names
        @rails_reserved_names ||= begin
          if defined?(ActionDispatch::ExceptionWrapper)
            Set.new(ActionDispatch::ExceptionWrapper.rescue_responses.keys.grep(String)).freeze
          else
            Set.new.freeze
          end
        end
      end

      private

      def _trane_handle_error(exception)
        klass = exception.class
        return _trane_unhandled_error(exception) unless klass.name

        index     = Trane.registry.errors_by_name
        error_def = index[klass.name] || _trane_short_name_match(index, klass)

        if error_def
          render(
            json: Trane.configuration.error_envelope.call(exception, error_def),
            status: error_def.status_code
          )
        elsif _trane_rails_reserved?(klass) && !Trane.configuration.rescue_rails_reserved
          raise exception
        else
          _trane_unhandled_error(exception)
        end
      end

      # rescue_from handles the exception BEFORE Rails' exception-reporting
      # middleware can see it, so without this hook a 500 in production
      # would leave no trace at all: no log line, no stacktrace, and no
      # event in middleware-based error trackers. Report through
      # Rails.error (the ErrorReporter interface trackers subscribe to)
      # and write the class + message + backtrace to the log.
      def _trane_report_unhandled(exception)
        return unless defined?(Rails)

        if Rails.respond_to?(:error) && Rails.error
          Rails.error.report(exception, handled: true, source: "trane")
        end

        if Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error(
            "[Trane] unhandled #{exception.class}: #{exception.message}\n" \
            "#{Array(exception.backtrace).first(20).join("\n")}"
          )
        end
      end

      # Short-name fallback, restricted to errors REGISTERED by short name.
      # The errors_by_name index also aliases FQDN registrations under their
      # demodulized name (BootValidator resolves operation error_keys through
      # those aliases), but matching here through an alias would let an
      # unrelated exception (SomeGem::UserNotFound) hijack a registered
      # Errors::UserNotFound and send a foreign library's message to the
      # client — FQDN registrations must match exactly.
      def _trane_short_name_match(index, klass)
        short     = klass.name.rpartition("::").last
        candidate = index[short]
        candidate if candidate && candidate.key == short
      end

      def _trane_rails_reserved?(klass)
        names = ErrorHandler.rails_reserved_names
        return false if names.empty?

        klass.ancestors.any? { |ancestor| names.include?(ancestor.name) }
      end

      # The report is NOT the envelope's concern and stays unconditional: this
      # rescue_from runs before Rails' exception-reporting middleware, so
      # without it a 500 in production leaves no log line and no tracker event.
      def _trane_unhandled_error(exception)
        _trane_report_unhandled(exception)

        render(
          json: Trane.configuration.error_envelope.call(exception, nil),
          status: :internal_server_error
        )
      end
    end
  end
end
