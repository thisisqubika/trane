# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/string/inflections"

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
    # the Trane lookup wins over the re-raise path.
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

      # Returns the frozen array of Rails-reserved exception classes derived
      # from ActionDispatch::ExceptionWrapper.rescue_responses. Memoized on
      # first call (after Rails boot completes). Returns [] when Rails is
      # not loaded.
      #
      # NOTE: callers MUST invoke this post-boot. The Rails Engine initializers
      # merge AR/AC entries into `rescue_responses` during boot; calling this
      # earlier would memoize an incomplete list. In practice the first error
      # arrives in a request thread, which is always post-boot — but tests or
      # explicit pre-boot invocations would have to reset @rails_reserved_classes
      # afterwards.
      def self.rails_reserved_classes
        @rails_reserved_classes ||= begin
          if defined?(ActionDispatch::ExceptionWrapper)
            ActionDispatch::ExceptionWrapper
              .rescue_responses
              .keys
              .filter_map { |name| name.is_a?(String) ? name.safe_constantize : nil }
              .freeze
          else
            [].freeze
          end
        end
      end

      private

      def _trane_handle_error(exception)
        klass = exception.class
        return _trane_unhandled_error(exception) unless klass.name

        index     = Trane.registry.errors_by_name
        error_def = index[klass.name] || index[klass.name.rpartition("::").last]

        if error_def
          render(
            json: { errors: [ { key: error_def.key.to_s, message: exception.message } ] },
            status: error_def.status_code
          )
        elsif _trane_rails_reserved?(klass)
          raise exception
        else
          _trane_unhandled_error(exception)
        end
      end

      def _trane_rails_reserved?(klass)
        ErrorHandler.rails_reserved_classes.any? { |reserved| klass <= reserved }
      end

      def _trane_unhandled_error(exception)
        if defined?(Rails) && !Rails.env.production?
          render(
            json: {
              errors: [ {
                key: "InternalServerError",
                message: "#{exception.class}: #{exception.message}"
              } ]
            },
            status: :internal_server_error
          )
        else
          render(
            json: { errors: [ { key: "InternalServerError", message: "An unexpected error occurred" } ] },
            status: :internal_server_error
          )
        end
      end
    end
  end
end
