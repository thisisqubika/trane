# frozen_string_literal: true

require "erb"

module Trane
  module Docs
    class HtmlRenderer
      METHOD_COLORS = {
        "GET" => "#61affe",
        "POST" => "#49cc90",
        "PUT" => "#fca130",
        "PATCH" => "#fca130",
        "DELETE" => "#f93e3e"
      }.freeze

      TEMPLATE_PATH = File.expand_path("templates/index.html.erb", __dir__)
      TEMPLATE      = ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-").freeze

      def self.render(definition)
        new(definition).to_html
      end

      def initialize(definition)
        @definition = definition
      end

      def to_html
        TEMPLATE.result(binding)
      end

      private

      def service
        @definition[:service]
      end

      def operations
        @definition[:operations] || []
      end

      def representations
        @definition[:representations] || []
      end

      def errors
        @definition[:errors] || []
      end

      def method_color(method)
        METHOD_COLORS[method.to_s.upcase] || "#999"
      end

      def h(text)
        ERB::Util.html_escape(text.to_s)
      end

      def representation_link(type_name)
        type_str = type_name.to_s
        reps = representations.map { |r| r[:name] }
        if reps.include?(type_str)
          "<a href=\"#rep-#{h(type_str)}\" class=\"type-link\">#{h(type_str)}</a>"
        else
          "<span class=\"type\">#{h(type_str)}</span>"
        end
      end

      def render_field_row(field, indent = 0, include_required: false, buffer: +"")
        name         = h(field[:name])
        type         = field[:type] || "object"
        type_display = if field[:array_of]
                         "array of #{representation_link(field[:array_of])}"
                       else
                         representation_link(type)
                       end
        extra_badge  = field[:extra] ? ' <span class="badge extra">extra</span>' : ""
        format_badge = field[:format] ? " <span class=\"badge format\">#{h(field[:format])}</span>" : ""
        enum_display = field[:enum] ? %(<div class="enum-values">enum: #{field[:enum].map { |v| h(v) }.join(", ")}</div>) : ""
        padding      = indent * 20

        buffer << %(<tr><td style="padding-left: #{padding + 12}px"><code>#{name}</code>#{extra_badge}</td>)
        buffer << %(<td>#{type_display}#{format_badge}#{enum_display}</td>)

        if include_required
          required_badge = case field[:required]
                           when true  then '<span class="badge required">required</span>'
                           when false then '<span class="badge optional">optional</span>'
                           else "—"
                           end
          buffer << %(<td>#{required_badge}</td>)
        end

        buffer << "</tr>\n"

        if field[:children]
          field[:children].each do |child|
            render_field_row(child, indent + 1, include_required: include_required, buffer: buffer)
          end
        end

        buffer
      end
    end
  end
end
