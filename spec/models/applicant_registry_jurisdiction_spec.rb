# frozen_string_literal: true

require "rails_helper"

# MH-310: "xu" (Utopia) is a UAT-only jurisdiction. A tampered param must not be
# able to create an applicant on it where SYNTHETIC_DATA_ENABLED is off.
RSpec.describe Applicant, "#registry_jurisdiction" do
  subject(:applicant) { build(:applicant, registry_jurisdiction: jurisdiction) }

  context "when synthetic data is disabled" do
    include_context "with synthetic data disabled"

    context "with xu" do
      let(:jurisdiction) { "xu" }

      it "is invalid, with the error on registry_jurisdiction" do
        expect(applicant).not_to be_valid
        expect(applicant.errors[:registry_jurisdiction]).to be_present
      end
    end

    %w[gb mt cy].each do |code|
      context "with #{code}" do
        let(:jurisdiction) { code }

        it { is_expected.to be_valid }
      end
    end

    context "with no jurisdiction" do
      let(:jurisdiction) { nil }

      it { is_expected.to be_valid }
    end
  end

  context "when an existing Utopia applicant is edited after the gate is switched off" do
    include_context "with synthetic data disabled"

    let(:jurisdiction) { "xu" }

    def with_synthetic_data(value)
      original = Rails.application.config.x.synthetic_data_enabled
      Rails.application.config.x.synthetic_data_enabled = value
      yield
    ensure
      Rails.application.config.x.synthetic_data_enabled = original
    end

    it "stays valid, because the jurisdiction is not being changed" do
      saved = with_synthetic_data(true) { create(:applicant, registry_jurisdiction: "xu") }

      saved.name = "Renamed Utopia Co"

      expect(saved).to be_valid
    end

    it "is invalid if the jurisdiction is set to xu again while the gate is off" do
      other = create(:applicant, registry_jurisdiction: "gb")
      other.registry_jurisdiction = "xu"

      expect(other).not_to be_valid
    end
  end

  context "when synthetic data is enabled" do
    include_context "with synthetic data enabled"

    context "with xu" do
      let(:jurisdiction) { "xu" }

      it { is_expected.to be_valid }
    end

    context "with gb" do
      let(:jurisdiction) { "gb" }

      it { is_expected.to be_valid }
    end
  end
end
