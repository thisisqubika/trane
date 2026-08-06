# frozen_string_literal: true

module Trane
  module Docs
    # Rack middleware-style app that serves documentation endpoints.
    # Mounted by the Trane::Engine at the path chosen by the host application.
    class App
      def call(env)
        request = Rack::Request.new(env)
        if request.path_info.end_with?(".json")
          serve_json
        else
          serve_html
        end
      end

      private

      def serve_json
        [200, { "content-type" => "application/json; charset=utf-8" }, [Cache.json]]
      end

      def serve_html
        [200, { "content-type" => "text/html; charset=utf-8" }, [Cache.html]]
      end
    end
  end
end
