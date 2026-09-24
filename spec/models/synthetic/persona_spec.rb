# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::Persona, type: :model do
  subject(:persona) { build(:synthetic_persona) }

  it { is_expected.to validate_presence_of(:given_names) }
  it { is_expected.to validate_presence_of(:surname) }
  it { is_expected.to validate_presence_of(:date_of_birth) }

  it {
    expect(persona).to define_enum_for(:sex)
      .with_values(female: "female", male: "male", unspecified: "unspecified")
      .with_default(:unspecified)
      .backed_by_column_of_type(:string)
  }

  describe "#full_name" do
    it "joins given names and surname" do
      persona.given_names = "Alex"
      persona.surname = "Testperson"

      expect(persona.full_name).to eq("Alex Testperson")
    end
  end

  describe "slug assignment" do
    it "parameterizes the full name" do
      persona = create(:synthetic_persona, given_names: "Jordan", surname: "Example")

      expect(persona.slug).to eq("jordan-example")
    end

    it "de-duplicates a colliding slug" do
      create(:synthetic_persona, given_names: "Jordan", surname: "Example")
      second = create(:synthetic_persona, given_names: "Jordan", surname: "Example")

      expect(second.slug).to eq("jordan-example-2")
    end

    it "does not overwrite an explicitly assigned slug" do
      persona = create(:synthetic_persona, slug: "custom-slug")

      expect(persona.slug).to eq("custom-slug")
    end
  end
end
