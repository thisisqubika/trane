# frozen_string_literal: true

module Trane
  # Prepended globally onto ActionDispatch::Routing::Mapper by the Engine
  # initializer `trane.prepend_routing_extension`. Available in all
  # `routes.draw` blocks. Routes without `contract:` pass through unchanged
  # in O(1).
  #
  # Uses `*path_or_actions, **kwargs` to mirror Rails' own `Mapper::Resources#match`
  # signature and handle every internal calling convention (normal path, hash-
  # shorthand `"up" => "ctrl#action"`, zero-positional-arg `match` calls, etc.).
  module RoutingExtension
    # Single source of truth for the keys accepted inside `contract: { ... }`.
    # Anything else is a typo and must fail loud at route-draw time rather
    # than being silently ignored or deferred to request time.
    CONTRACT_KEYS = %i[operation].freeze

    # Intercepts route declarations that carry `contract: { operation: name }`.
    # Strips the key, injects the operation name into `defaults[:_trane_operation]`
    # (used at request time to resolve the contract), and sets `as: name` so the
    # operation is discoverable as a named-route prefix in `bin/rails routes`.
    #
    # Routes without `contract:` are forwarded to super unchanged.
    #
    # Rails 7.x / 8.0 call match(*args, options_hash) via map_method — a plain
    # Hash as the last positional argument. Rails 8.1+ uses proper keyword
    # arguments. Both conventions must be handled here.
    def match(*path_or_actions, **kwargs)
      if kwargs.key?(:contract)
        # Rails 8.1+ keyword-argument path
        kwargs = kwargs.dup
        contract = kwargs.delete(:contract)
        _inject_trane_contract!(nil, kwargs, contract)
      elsif path_or_actions.last.is_a?(Hash) && path_or_actions.last.key?(:contract)
        # Rails 7.x / 8.0 positional-hash path (map_method calls match(*args, opts))
        path_or_actions = path_or_actions.dup
        options = path_or_actions.last.dup
        path_or_actions[-1] = options
        contract = options.delete(:contract)
        _inject_trane_contract!(options, nil, contract)
      end

      super(*path_or_actions, **kwargs)
    end

    private

    # Mutates either +options+ (positional hash) or +kwargs+ (keyword hash) in-place.
    def _inject_trane_contract!(options, kwargs, contract)
      _validate_contract_hash!(contract)

      target = options || kwargs
      operation = contract[:operation].to_s
      defaults = target[:defaults] || {}
      target[:defaults] = defaults.merge(_trane_operation: operation)
      # Set :as to the operation name unless the caller already provided an
      # explicit Symbol or String. ActionDispatch::Routing::Mapper uses a
      # private DEFAULT = Object.new sentinel for "not set by user", which is
      # truthy, so `target[:as] ||= operation` would silently skip it.
      user_as = target[:as]
      target[:as] = operation unless user_as.is_a?(Symbol) || user_as.is_a?(String)
    end

    # Fails loud on malformed `contract:` metadata: unknown keys (typos) are
    # reported first — with a "Did you mean?" suggestion when one is close —
    # followed by a check that :operation is present and non-blank. Checking
    # unknown keys first means a typo like `operaton:` is reported as an
    # unknown key (with a suggestion) rather than as a missing :operation.
    def _validate_contract_hash!(contract)
      contract = {} unless contract.is_a?(Hash)

      unknown = contract.keys - CONTRACT_KEYS
      unless unknown.empty?
        bad = unknown.first
        message = "Unknown key `#{bad}` in contract:."
        suggestion = Trane.spelling_suggestion(bad, CONTRACT_KEYS)
        message += " Did you mean `#{suggestion}`?" if suggestion
        raise Trane::RoutingContractError, message
      end

      op = contract[:operation]
      raise Trane::RoutingContractError, "contract: requires a non-empty :operation" if op.nil? || op.to_s.strip.empty?
    end
  end
end
