# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ExtractionPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:presenter) { described_class.new(applicant, template) }

  describe "#pending_count" do
    it "counts only confirmed, pending documents" do
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
      create(:kyc_document, applicant: applicant, classification_status: :auto_classified, status: :pending)
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

      expect(presenter.pending_count).to eq(2)
    end
  end

  describe "#pending?" do
    it "is false when there are no pending confirmed documents" do
      expect(presenter.pending?).to be false
    end

    it "is true when there is at least one pending confirmed document" do
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
      expect(presenter.pending?).to be true
    end
  end

  describe "#pending_count_label" do
    it "states the scope with the count" do
      create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
      expect(presenter.pending_count_label).to eq("1 document pending extraction")
    end
  end

  describe "#confirm_message" do
    it "states there is nothing to extract when the count is zero" do
      expect(presenter.confirm_message).to eq("There are no pending documents to extract.")
    end

    it "states the scope with the count when documents are pending" do
      create_list(:kyc_document, 3, applicant: applicant, classification_status: :confirmed, status: :pending)
      expect(presenter.confirm_message).to eq("Run extraction on 3 pending documents?")
    end
  end
end
