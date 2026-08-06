# frozen_string_literal: true

module Trane
  # Thread-safe registry of operations, representations, and errors.
  #
  # The registry maintains a single frozen snapshot containing all three
  # categories. Reads (`Registry.operations`, etc.) are lock-free: one
  # ivar read returning a frozen Hash. Writes happen atomically via
  # `Registry.replace!`, which constructs a new snapshot in a builder
  # and swaps it in a single assignment (atomic under MRI GVL).
  #
  # For ad-hoc registrations outside `replace!` (specs, REPL), the
  # `register_*` methods do copy-on-write to a new snapshot — O(n) per
  # write but bounded by spec sizes (typically < 100 entries).
  #
  # Class methods on this module delegate to the current application's
  # `Registry::Instance` via `Trane.registry`. Existing call sites
  # (`Trane::Registry.reset!` etc.) continue to work unchanged.
  module Registry
    EMPTY_ERRORS_BY_NAME = {}.freeze

    EMPTY_SNAPSHOT = {
      operations:      {}.freeze,
      representations: {}.freeze,
      errors:          {}.freeze,
      errors_by_name:  EMPTY_ERRORS_BY_NAME
    }.freeze

    # Builder collected inside a `Registry::Instance#replace!` block.
    class SnapshotBuilder
      def initialize
        @operations      = {}
        @representations = {}
        @errors          = {}
      end

      def register_operation(definition)
        @operations[definition.name] = definition
      end

      def register_representation(definition)
        @representations[definition.name] = definition
      end

      def register_error(definition)
        @errors[definition.key] = definition
      end

      def freeze_and_build
        errors_by_name = build_errors_by_name(@errors)
        {
          operations:      @operations.freeze,
          representations: @representations.freeze,
          errors:          @errors.freeze,
          errors_by_name:  errors_by_name
        }.freeze
      end

      private

      # Build a frozen FQDN+short-name index over the given errors Hash.
      # Raises Trane::Error on short-name collision between two distinct FQDNs.
      def build_errors_by_name(errors)
        return EMPTY_ERRORS_BY_NAME if errors.empty?

        index   = {}
        buckets = Hash.new { |h, k| h[k] = [] }

        errors.each do |fqdn, defn|
          index[fqdn] = defn
          short = fqdn.rpartition("::").last
          buckets[short] << defn unless short == fqdn
        end

        buckets.each do |short, defs|
          if defs.size >= 2
            fqdns   = defs.map(&:key).sort
            message = "Trane boot: error short-name collision on \"#{short}\".\n" \
                      "Conflicting registrations: #{fqdns.join(', ')}.\n" \
                      "Fix by renaming one, or by referencing them by FQDN in operation `errors` blocks " \
                      "(e.g. key :\"#{fqdns.first}\")."
            raise Trane::Error, message
          end
          index[short] = defs.first unless index.key?(short)
        end

        index.freeze
      end
    end

    # Per-application Trane registry. Owns its own snapshot ivar and
    # replacement mutex; instances are independent of one another.
    class Instance
      def initialize
        @snapshot                       = EMPTY_SNAPSHOT
        @replace_mutex                  = Mutex.new
        @builder_key                    = :"trane_active_builder_#{object_id}"
        @compiled_serializers           = {}
        @validator_field_names          = {}
        @validator_declared_field_names = {}
      end

      def operations
        @snapshot[:operations]
      end

      def representations
        @snapshot[:representations]
      end

      def errors
        @snapshot[:errors]
      end

      # Returns the frozen FQDN+short-name index built when the snapshot was last replaced.
      # Keys are Strings; values are Trane::ErrorDefinition instances.
      def errors_by_name
        @snapshot[:errors_by_name]
      end

      # Atomic bulk replacement. Use this for reload paths (Railtie's
      # `to_prepare`, integration test setup). The block receives a
      # `SnapshotBuilder`; on successful completion of the block, the
      # built snapshot replaces the current one in a single assignment.
      # If the block raises, the prior snapshot is preserved.
      #
      # Concurrent writers are serialised by a per-instance mutex;
      # readers remain lock-free.
      #
      # Nested calls (on the same thread) are not supported and raise.
      def replace!
        raise Trane::Error, "nested Registry.replace! is not supported" if active_builder

        @replace_mutex.synchronize do
          builder = SnapshotBuilder.new
          Thread.current.thread_variable_set(@builder_key, builder)
          yield builder
          @snapshot = builder.freeze_and_build
          @compiled_serializers           = {}
          @validator_field_names          = {}
          @validator_declared_field_names = {}
        ensure
          Thread.current.thread_variable_set(@builder_key, nil)
        end
      end

      # Incremental registration paths. Used by specs and any caller
      # outside a `replace!` block. Copy-on-write under @replace_mutex,
      # so concurrent CoW writes are serialised with the same guarantee
      # as `replace!`. The `active_builder` early-return skips the mutex
      # acquisition when these methods are called from inside a
      # `replace!` block — re-acquiring a non-reentrant Mutex from the
      # same thread would deadlock. For bulk operations, prefer `replace!`.
      def register_operation(definition)
        b = active_builder
        return b.register_operation(definition) if b

        @replace_mutex.synchronize do
          s = @snapshot
          @snapshot = s.merge(operations: s[:operations].merge(definition.name => definition).freeze).freeze
          @compiled_serializers           = {}
          @validator_field_names          = {}
          @validator_declared_field_names = {}
        end
      end

      def register_representation(definition)
        b = active_builder
        return b.register_representation(definition) if b

        @replace_mutex.synchronize do
          s = @snapshot
          @snapshot = s.merge(representations: s[:representations].merge(definition.name => definition).freeze).freeze
          @compiled_serializers           = {}
          @validator_field_names          = {}
          @validator_declared_field_names = {}
        end
      end

      def register_error(definition)
        b = active_builder
        return b.register_error(definition) if b

        @replace_mutex.synchronize do
          s = @snapshot
          new_errors = s[:errors].merge(definition.key => definition).freeze
          new_index  = SnapshotBuilder.allocate.send(:build_errors_by_name, new_errors)
          @snapshot = s.merge(errors: new_errors, errors_by_name: new_index).freeze
          @compiled_serializers           = {}
          @validator_field_names          = {}
          @validator_declared_field_names = {}
        end
      end

      def reset!
        @snapshot                       = EMPTY_SNAPSHOT
        @compiled_serializers           = {}
        @validator_field_names          = {}
        @validator_declared_field_names = {}
      end

      def validate!
        Trane::BootValidator.validate!(self)
      end

      # Returns a memoized Trane::Serializer for the given ResponseDefinition
      # and strict_mode pair. Instances are built lazily on first access and
      # cached until the registry snapshot changes (via replace!, reset!, or
      # any of the register_* copy-on-write paths).
      #
      # Thread-safety: concurrent first access on the same key may build two
      # Serializers; last write wins. Subsequent reads share the cached
      # instance. Serializer is frozen post-init and safe to share across
      # threads.
      #
      # @param response_def [Trane::ResponseDefinition]
      # @param strict_mode [Symbol] :raise, :log, or :ignore
      # @return [Trane::Serializer]
      def compiled_serializer_for(response_def, strict_mode)
        key = [response_def.object_id, strict_mode]
        @compiled_serializers[key] ||= Trane::Serializer.new(response_def, self, strict_mode: strict_mode)
      end

      # Cached frozen Array of all field names for a given fields collection.
      # Used by ContractValidator to detect undeclared keys without per-request
      # allocation. Same lifecycle / invalidation as @compiled_serializers.
      #
      # @param fields [Array<Trane::FieldNode>] frozen fields array
      # @return [Array<Symbol>] frozen Array of field names
      def validator_field_names_for(fields)
        @validator_field_names[fields.object_id] ||= fields.map(&:name).freeze
      end

      # Cached frozen Array of non-`extra:` field names. Used by ContractValidator
      # to detect missing declared keys.
      #
      # @param fields [Array<Trane::FieldNode>] frozen fields array
      # @return [Array<Symbol>] frozen Array of declared (non-extra) field names
      def validator_declared_field_names_for(fields)
        @validator_declared_field_names[fields.object_id] ||=
          fields.reject(&:extra).map(&:name).freeze
      end

      private

      def active_builder
        Thread.current.thread_variable_get(@builder_key)
      end
    end

    class << self
      def operations;      Trane.registry.operations; end
      def representations; Trane.registry.representations; end
      def errors;          Trane.registry.errors; end

      # Delegates to the current application's Registry::Instance.
      def errors_by_name;  Trane.registry.errors_by_name; end

      def replace!(&block); Trane.registry.replace!(&block); end
      def register_operation(d);      Trane.registry.register_operation(d); end
      def register_representation(d); Trane.registry.register_representation(d); end
      def register_error(d);          Trane.registry.register_error(d); end
      def reset!;    Trane.registry.reset!; end
      def validate!; Trane.registry.validate!; end

      def validator_field_names_for(fields);          Trane.registry.validator_field_names_for(fields); end
      def validator_declared_field_names_for(fields); Trane.registry.validator_declared_field_names_for(fields); end
    end
  end
end
