# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Registry concurrent reads during reload", type: :integration do
  it "never returns nil for a registered op or representation during repeated reloads" do
    seed_op = Trane::OperationBuilder.new(:concurrent_op).build
    seed_rep = Trane::RepresentationBuilder.new(:concurrent_rep).build
    Trane::Registry.replace! do |b|
      b.register_operation(seed_op)
      b.register_representation(seed_rep)
    end

    errors = []
    readers = Array.new(4) do
      Thread.new do
        500.times do
          op = Trane::Registry.operations[:concurrent_op]
          rep = Trane::Registry.representations[:concurrent_rep]
          errors << "nil op"  if op.nil?
          errors << "nil rep" if rep.nil?
          Thread.pass
        end
      end
    end

    reloader = Thread.new do
      100.times do
        Trane::Registry.replace! do |b|
          b.register_operation(seed_op)
          b.register_representation(seed_rep)
        end
        Thread.pass
      end
    end

    (readers + [ reloader ]).each(&:join)
    expect(errors).to be_empty
  end
end
