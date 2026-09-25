# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::PersonaPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }
  let(:persona)     { build(:synthetic_persona) }

  it("psp_admin can index")   { expect(described_class.new(psp_admin, Synthetic::Persona).index?).to be true }
  it("psp_support cannot index") { expect(described_class.new(psp_support, Synthetic::Persona).index?).to be false }
  it("psp_admin can create")  { expect(described_class.new(psp_admin, persona).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support, persona).create?).to be false }
  it("psp_admin can generate_document")  { expect(described_class.new(psp_admin, persona).generate_document?).to be true }
  it("psp_support cannot generate_document") { expect(described_class.new(psp_support, persona).generate_document?).to be false }
  it("psp_admin can export")  { expect(described_class.new(psp_admin, persona).export?).to be true }
  it("psp_support cannot export") { expect(described_class.new(psp_support, persona).export?).to be false }
end
