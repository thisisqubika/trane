# frozen_string_literal: true

require "concurrent/atomic/count_down_latch"
require "concurrent/array"

RSpec.describe Trane::Registry do
  describe ".register_operation" do
    it "stores an operation by name" do
      op = Trane::OperationDefinition.new(name: :get_user, summary: "Get user")
      described_class.register_operation(op)

      expect(described_class.operations[:get_user]).to eq(op)
    end
  end

  describe ".register_representation" do
    it "stores a representation by name" do
      rep = Trane::RepresentationDefinition.new(name: :user, fields: [])
      described_class.register_representation(rep)

      expect(described_class.representations[:user]).to eq(rep)
    end
  end

  describe ".register_error" do
    it "stores an error by string key" do
      err = Trane::ErrorDefinition.new(key: :UserNotFound, status_code: 404, description: "Not found")
      described_class.register_error(err)

      expect(described_class.errors["UserNotFound"]).to eq(err)
    end
  end

  describe ".reset!" do
    it "clears all registries" do
      described_class.register_operation(
        Trane::OperationDefinition.new(name: :test)
      )
      described_class.register_representation(
        Trane::RepresentationDefinition.new(name: :test)
      )
      described_class.register_error(
        Trane::ErrorDefinition.new(key: :Test, status_code: 500, description: "test")
      )

      described_class.reset!

      expect(described_class.operations).to be_empty
      expect(described_class.representations).to be_empty
      expect(described_class.errors).to be_empty
    end
  end

  describe ".replace!" do
    it "publishes all registrations atomically after the block" do
      op = Trane::OperationBuilder.new(:get_user).build
      described_class.replace! do |b|
        b.register_operation(op)
      end
      expect(described_class.operations[:get_user]).to eq(op)
    end

    it "preserves the prior snapshot when the block raises" do
      op_a = Trane::OperationBuilder.new(:get_user).build
      described_class.replace! { |b| b.register_operation(op_a) }

      op_b = Trane::OperationBuilder.new(:create_user).build
      expect {
        described_class.replace! do |b|
          b.register_operation(op_b)
          raise "boom"
        end
      }.to raise_error("boom")

      expect(described_class.operations.keys).to eq([ :get_user ])
    end

    it "raises on nested replace!" do
      described_class.replace! do |_b|
        expect { described_class.replace! { } }.to raise_error(Trane::Error, /nested/)
      end
    end

    it "clears the thread-local builder after the block completes" do
      described_class.replace! { |_b| }
      expect(Thread.current.thread_variable_get(:trane_active_builder)).to be_nil
    end

    it "clears the thread-local builder when the block raises" do
      expect {
        described_class.replace! { |_b| raise "boom" }
      }.to raise_error("boom")
      expect(Thread.current.thread_variable_get(:trane_active_builder)).to be_nil
    end
  end

  describe ".replace! under concurrent writers" do
    it "commits one thread's complete snapshot per call (no torn merges)" do
      50.times do |iteration|
        described_class.reset!
        thread_count = 8
        ops_per_thread = 8
        latch = Concurrent::CountDownLatch.new(thread_count)
        threads = Array.new(thread_count) do |t|
          Thread.new do
            latch.count_down
            latch.wait
            described_class.replace! do |b|
              ops_per_thread.times do |i|
                b.register_operation(
                  Trane::OperationBuilder.new(:"thread_#{t}_op_#{i}").build
                )
              end
            end
          end
        end
        threads.each(&:join)

        keys = described_class.operations.keys
        expect(keys.size).to eq(ops_per_thread),
          "iteration #{iteration}: expected exactly #{ops_per_thread} ops, got #{keys.size} (#{keys.inspect})"
        prefixes = keys.map { |k| k.to_s.split("_op_").first }.uniq
        expect(prefixes.size).to eq(1),
          "iteration #{iteration}: torn snapshot — keys from multiple threads: #{prefixes.inspect}"
      end
    end

    it "allows readers to observe the previous frozen snapshot while a writer holds the lock" do
      described_class.replace! do |b|
        b.register_operation(Trane::OperationBuilder.new(:initial_op).build)
      end

      reader_observations = Concurrent::Array.new
      reader_done = Concurrent::CountDownLatch.new(1)

      writer = Thread.new do
        described_class.replace! do |b|
          reader = Thread.new do
            20.times do
              reader_observations << described_class.operations
            end
            reader_done.count_down
          end
          reader_done.wait
          reader.join
          b.register_operation(Trane::OperationBuilder.new(:new_op).build)
        end
      end
      writer.join

      expect(reader_observations).not_to be_empty
      expect(reader_observations).to all(satisfy { |s| s.frozen? && s.key?(:initial_op) })
    end
  end

  describe "incremental .register_operation outside replace!" do
    it "writes via copy-on-write" do
      op = Trane::OperationBuilder.new(:get_user).build
      described_class.register_operation(op)
      expect(described_class.operations[:get_user]).to eq(op)
    end
  end

  describe "concurrent CoW register_error" do
    it "serializes concurrent CoW register_error calls without losing registrations" do
      Trane::Registry.reset!

      thread_count = 25
      start_signal = Queue.new

      threads = thread_count.times.map do |i|
        Thread.new do
          start_signal.pop
          Trane::Registry.register_error(
            Trane::ErrorDefinition.new(
              key: "MyApp::Errors::Concurrent#{i}",
              status_code: 500,
              description: "err"
            )
          )
        end
      end

      thread_count.times { start_signal << :go }
      threads.each(&:join)

      expect(Trane::Registry.errors.size).to eq(thread_count)
      expect(Trane::Registry.errors_by_name.size).to eq(thread_count * 2)
    end
  end

  describe ".replace! under fiber scheduling" do
    it "guards against nested replace! invoked from a fiber on the same OS thread" do
      nested_error = nil
      described_class.replace! do |_b|
        Fiber.new do
          described_class.replace! { |_inner| }
        rescue Trane::Error => e
          nested_error = e
        end.resume
      end

      expect(nested_error).to be_a(Trane::Error)
      expect(nested_error.message).to include("nested")
    end

    it "isolates the builder slot across independent threads" do
      observed_in_other_thread = :placeholder
      described_class.replace! do |_b|
        t = Thread.new do
          observed_in_other_thread =
            Thread.current.thread_variable_get(:trane_active_builder)
        end
        t.join
      end

      expect(observed_in_other_thread).to be_nil
    end
  end
end
