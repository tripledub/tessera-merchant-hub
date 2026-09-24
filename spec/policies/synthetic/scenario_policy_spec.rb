# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::ScenarioPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }

  it("psp_admin can index")   { expect(described_class.new(psp_admin, Synthetic::ScenarioCatalogue::Scenario).index?).to be true }
  it("psp_support cannot index") { expect(described_class.new(psp_support, Synthetic::ScenarioCatalogue::Scenario).index?).to be false }
  it("psp_admin can download")   { expect(described_class.new(psp_admin, Synthetic::ScenarioCatalogue::Scenario).download?).to be true }
  it("psp_support cannot download") { expect(described_class.new(psp_support, Synthetic::ScenarioCatalogue::Scenario).download?).to be false }
end
