# frozen_string_literal: true

require "spec_helper"

# Memory-retention regression guard for the two hot paths, distilled from the
# 2026-08 memory leak audit (docs/handoff-memory-leaks.md): the steady-state
# request path and the reload path must stay flat — every per-iteration
# allocation must be collectable once the iteration ends.
#
# Methodology: force full GC before and after the workload and compare
# GC.stat[:heap_live_slots]. Healthy baselines measure a few dozen slots of
# drift; a leak of one retained object per iteration measures at least
# ITERATIONS slots. The threshold sits far above the former and far below the
# latter, so the assertion is loose enough not to flake and tight enough to
# catch any real per-iteration retention.
RSpec.describe "Memory retention regression" do
  let(:iterations)     { 10_000 }
  let(:slot_tolerance) { 2_000 }

  def full_gc
    4.times { GC.start(full_mark: true, immediate_sweep: true) }
  end

  # Returns the live-slot delta caused by the block, after full GC on both sides.
  def live_slot_delta
    full_gc
    before = GC.stat[:heap_live_slots]
    yield
    full_gc
    GC.stat[:heap_live_slots] - before
  end

  def build_operation
    Trane::OperationDefinition.new(name: :show_user, responses: {
      200 => Trane::ResponseDefinition.new(status: 200, fields: [
        Trane::FieldNode.new(name: :id, type: :integer),
        Trane::FieldNode.new(name: :name, type: :string),
        Trane::FieldNode.new(name: :secret, type: :string, extra: true)
      ])
    })
  end

  it "keeps the steady-state request path flat (serialize via cached serializer)" do
    instance = Trane::Registry::Instance.new
    instance.replace! { |b| b.register_operation(build_operation) }
    response_def = instance.operations[:show_user].responses[200]
    data = { id: 1, name: "x", secret: "s" }

    # Warm the serializer cache so first-build allocations don't count.
    instance.compiled_serializer_for(response_def, :raise).serialize(data)

    delta = live_slot_delta do
      iterations.times { instance.compiled_serializer_for(response_def, :raise).serialize(data) }
    end

    expect(delta.abs).to be < slot_tolerance
  end

  it "keeps the reload path flat (replace! on the same instance)" do
    instance = Trane::Registry::Instance.new
    instance.replace! { |b| b.register_operation(build_operation) }

    delta = live_slot_delta do
      (iterations / 10).times { instance.replace! { |b| b.register_operation(build_operation) } }
    end

    expect(delta.abs).to be < slot_tolerance
  end
end
