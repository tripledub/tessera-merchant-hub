# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::ReadOnlyRecord, type: :model do
  it "is an abstract class" do
    expect(described_class.abstract_class).to be true
  end

  it "returns true from readonly? on concrete subclasses" do
    # Cannot instantiate abstract class directly; verify via a concrete subclass
    expect(Tessera::Payment.new.readonly?).to be true
  end
end
