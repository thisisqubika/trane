# frozen_string_literal: true

require "set"

module Trane
  module ExtraAttributesFilter
    # Hard cap on the number of extra_attributes values accepted from
    # a single request. Defense-in-depth against a crafted query string
    # that would otherwise allocate an arbitrarily large Set. Rack caps
    # total param keys per request upstream; this caps how many of those
    # Trane itself will materialise into a Set for one filter.
    #
    # Sized well above any realistic legitimate API surface (single
    # endpoints typically declare < 20 extra fields).
    MAX_VALUES = 100

    # Frozen, shared sentinel returned for every input that parses to no
    # extras (nil, non-iterable, or empty Array). Safe to share — callers
    # only read via `include?` (audited: serializer.rb:48 is the sole
    # consumer; zero mutations across trane/lib/).
    EMPTY = Set.new.freeze

    # Parse extra_attributes from request params into a Set of dot-notation paths.
    #
    # @param params [Hash, ActionController::Parameters] request params
    # @return [Set<String>]
    def self.parse(params)
      raw = params[:extra_attributes]
      return EMPTY if raw.nil?

      values = case raw
      when Array then raw
      when String then [ raw ]
      else []
      end

      return EMPTY if values.empty?
      Set.new(values.first(MAX_VALUES).map(&:to_s))
    end
  end
end
