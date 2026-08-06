# frozen_string_literal: true

require_relative "integration_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "contracts_paths multi-path loading", type: :integration do
  def restore_configuration_and_registry(original_paths)
    Trane.configuration.instance_variable_set(:@frozen, false)
    Trane.configuration.instance_variable_set(:@contracts_paths, original_paths)
    Trane.configuration.instance_variable_set(:@frozen, true)
    Rails.application.reloader.prepare!
  end

  it "loads contracts from a custom contracts_path and registers operations" do
    original_paths = Trane.configuration.instance_variable_get(:@contracts_paths)

    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "operations"))

      File.write(File.join(tmpdir, "errors.rb"), <<~RUBY)
        # frozen_string_literal: true
      RUBY

      File.write(File.join(tmpdir, "operations", "audit2_07_test.rb"), <<~RUBY)
        # frozen_string_literal: true
        Trane.operation :audit2_07_test_op do
          summary "AUDIT2-07 test operation"
          response 200 do
            field :ok, type: :boolean
          end
        end
      RUBY

      begin
        Trane.configuration.instance_variable_set(:@frozen, false)
        Trane.configuration.instance_variable_set(:@contracts_paths, [tmpdir])
        Trane.configuration.instance_variable_set(:@frozen, true)

        Rails.application.reloader.prepare!

        expect(Trane.registry.operations.key?(:audit2_07_test_op)).to be(true)
      ensure
        restore_configuration_and_registry(original_paths)
      end
    end
  end

  it "applies errors-first ordering across multiple paths" do
    original_paths = Trane.configuration.instance_variable_get(:@contracts_paths)

    Dir.mktmpdir do |base1|
      Dir.mktmpdir do |base2|
        FileUtils.mkdir_p(File.join(base1, "operations"))
        FileUtils.mkdir_p(File.join(base2, "representations"))

        File.write(File.join(base1, "errors.rb"), <<~RUBY)
          # frozen_string_literal: true
          Trane.errors do
            error :MultiPathTestError, status_code: 422, description: "test"
          end
        RUBY

        File.write(File.join(base2, "representations", "multi_path_entity.rb"), <<~RUBY)
          # frozen_string_literal: true
          Trane.representation :multi_path_entity do
            field :id, type: :integer
          end
        RUBY

        File.write(File.join(base1, "operations", "multi_path_ops.rb"), <<~RUBY)
          # frozen_string_literal: true
          Trane.operation :multi_path_test_op do
            summary "Multi-path test operation"
            response 200 do
              field :entity, type: :multi_path_entity
            end
            errors do
              key :MultiPathTestError
            end
          end
        RUBY

        begin
          Trane.configuration.instance_variable_set(:@frozen, false)
          Trane.configuration.instance_variable_set(:@contracts_paths, [base1, base2])
          Trane.configuration.instance_variable_set(:@frozen, true)

          expect { Rails.application.reloader.prepare! }.not_to raise_error

          expect(Trane.registry.operations.key?(:multi_path_test_op)).to be(true)
          expect(Trane.registry.representations.key?(:multi_path_entity)).to be(true)
          expect(Trane.registry.errors.key?("MultiPathTestError")).to be(true)
        ensure
          restore_configuration_and_registry(original_paths)
        end
      end
    end
  end
end
