# frozen_string_literal: true

module Trane
  # Single source of truth for the contract-file load order, used by both
  # the Engine's to_prepare block and any test harness that replays the
  # boot-time load (spec/integration/integration_helper.rb) — keeping the
  # two from silently diverging.
  #
  # Order:
  #   Phase 1 — every errors.rb from every base path (in declaration order).
  #   Phase 2 — all other .rb files from every base path (sorted within each).
  module ContractLoader
    # Yields the absolute path (String) of each contract file in load order.
    #
    # @param root [Pathname] the application root (e.g. Rails.root)
    # @param contracts_paths [Array<String>] base paths relative to root
    def self.each_file(root, contracts_paths)
      errors_files = contracts_paths.map { |path| root.join(path, "errors.rb") }
      errors_files.each { |file| yield file.to_s if file.exist? }

      contracts_paths.each_with_index do |path, i|
        errors_file = errors_files[i].to_s
        Dir[root.join(path, "**/*.rb")].sort.each do |file|
          yield file unless file == errors_file
        end
      end
    end
  end
end
