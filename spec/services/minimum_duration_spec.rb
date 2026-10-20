# frozen_string_literal: true

require "rails_helper"

# MH-406: pads a block to a minimum duration so a known and an unknown address
# take the same time to answer.
RSpec.describe MinimumDuration do
  let(:now) { [ 0.0 ] }
  let(:clock) { -> { now.first } }

  before do
    allow(described_class).to receive(:pause) { |seconds| now[0] += seconds }
  end

  it "returns what the block returns" do
    expect(described_class.call(0.4, clock: clock) { :done }).to eq(:done)
  end

  it "waits for whatever is left of the minimum when the block is quick" do
    described_class.call(0.4, clock: clock) { now[0] += 0.1 }

    expect(described_class).to have_received(:pause).with(be_within(0.0001).of(0.3))
    expect(now.first).to be_within(0.0001).of(0.4)
  end

  it "does not wait at all when the block already took longer" do
    described_class.call(0.4, clock: clock) { now[0] += 0.9 }

    expect(described_class).not_to have_received(:pause)
  end

  it "pads when the block raises, then lets the error through" do
    expect { described_class.call(0.4, clock: clock) { raise ArgumentError, "boom" } }.to raise_error(ArgumentError, "boom")

    expect(described_class).to have_received(:pause).with(be_within(0.0001).of(0.4))
  end

  it "really sleeps by default" do
    allow(described_class).to receive(:pause).and_call_original
    allow(Kernel).to receive(:sleep)

    described_class.call(0.05) { nil }

    expect(Kernel).to have_received(:sleep).with(be > 0)
  end
end
