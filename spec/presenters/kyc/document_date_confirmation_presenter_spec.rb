# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentDateConfirmationPresenter, type: :presenter do
  let_it_be(:actor) { create(:user, :psp_admin) }
  let(:template) { ApplicationController.new.view_context }
  let(:presenter) { described_class.new(document, template) }

  let(:document) do
    create(:kyc_document, validity_dates: {
      "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01", "confidence" => 0.95,
                    "provenance" => "ai_extraction" },
      "issued" => { "raw" => "not-a-date", "normalized" => nil, "confidence" => nil,
                    "provenance" => "ai_extraction" }
    })
  end

  describe "#date_roles" do
    it "returns the roles present in validity_dates" do
      expect(presenter.date_roles).to contain_exactly("expiry", "issued")
    end
  end

  describe "#extracted_value_for" do
    it "returns the normalized extracted value for a role" do
      expect(presenter.extracted_value_for("expiry")).to eq("2030-01-01")
    end

    it "returns nil when the role has no normalized value" do
      expect(presenter.extracted_value_for("issued")).to be_nil
    end
  end

  describe "#current_confirmation_for" do
    it "returns nil when there is no confirmation yet" do
      expect(presenter.current_confirmation_for("expiry")).to be_nil
    end

    it "returns the current confirmation once one exists" do
      confirmation = Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )

      expect(presenter.current_confirmation_for("expiry")).to eq(confirmation)
    end
  end

  describe "#confirmed?" do
    it "is false when the role has not been confirmed" do
      expect(presenter.confirmed?("expiry")).to be(false)
    end

    it "is true once the role has a confirmation" do
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2030, 1, 1), confirmed_by: actor
      )

      expect(presenter.confirmed?("expiry")).to be(true)
    end
  end

  describe "#form_default_value_for" do
    it "defaults to the extracted value when unconfirmed" do
      expect(presenter.form_default_value_for("expiry")).to eq("2030-01-01")
    end

    it "defaults to blank when unconfirmed and nothing was extracted" do
      expect(presenter.form_default_value_for("issued")).to be_nil
    end

    it "defaults to the current confirmed value once confirmed" do
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2031, 6, 1), confirmed_by: actor, reason: "Renewed"
      )

      expect(presenter.form_default_value_for("expiry")).to eq(Date.new(2031, 6, 1).iso8601)
    end
  end
end
