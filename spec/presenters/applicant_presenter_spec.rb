# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:presenter) { described_class.new(applicant, template) }

  describe "#status_badge" do
    it "returns amber badge for pending" do
      html = presenter.status_badge
      expect(html).to include("Pending")
      expect(html).to include("bg-amber-50")
    end

    it "returns green badge for approved" do
      applicant.update!(status: :approved)
      html = presenter.status_badge
      expect(html).to include("Approved")
      expect(html).to include("bg-green-50")
    end

    it "returns red badge for rejected" do
      applicant.update!(status: :rejected)
      html = presenter.status_badge
      expect(html).to include("Rejected")
      expect(html).to include("bg-red-50")
    end
  end

  describe "#detail_rows" do
    it "includes company when present" do
      applicant.update!(company_name: "Acme Ltd")
      rows = presenter.detail_rows
      expect(rows).to include(a_hash_including(label: "Company", value: "Acme Ltd"))
    end

    it "excludes company when blank" do
      applicant.update!(company_name: nil)
      labels = presenter.detail_rows.map { |r| r[:label] }
      expect(labels).not_to include("Company")
    end
  end

  describe "counts" do
    it "counts principals" do
      create(:kyc_principal, applicant: applicant, name: "Alice Smith")
      expect(presenter.principal_count).to eq(1)
    end

    it "counts documents" do
      create(:kyc_document, applicant: applicant)
      expect(presenter.document_count).to eq(1)
    end

    it "counts only unacknowledged warnings" do
      doc = create(:kyc_document, applicant: applicant, document_type: :group_structure_chart)
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc)

      create(:kyc_validation_warning, applicant: applicant, kyc_document: doc, corporate_entity: entity, acknowledged: false)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: doc, corporate_entity: entity, acknowledged: true)

      expect(presenter.warning_count).to eq(1)
      expect(presenter.total_warning_count).to eq(2)
    end
  end

  describe "#warning_count_class" do
    it "returns red class when warnings exist" do
      doc = create(:kyc_document, applicant: applicant, document_type: :group_structure_chart)
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: doc, corporate_entity: entity)

      expect(presenter.warning_count_class).to include("text-red-600")
    end

    it "returns gray class when no warnings" do
      expect(presenter.warning_count_class).to include("text-gray-800")
    end
  end

  describe "#registry_lookup_banner" do
    let(:applicant) { create(:applicant, company_number: "12345678") }
    let(:scope) { "applicants.tabs.overview.registry_lookup" }

    it "is nil without a company number" do
      applicant.update!(company_number: nil)

      expect(presenter.registry_lookup_banner).to be_nil
    end

    it "offers a fetch when never attempted" do
      banner = presenter.registry_lookup_banner

      expect(banner.message).to eq(I18n.t("#{scope}.never_attempted"))
      expect(banner.action_label).to eq(I18n.t("#{scope}.fetch"))
    end

    it "is nil after a successful lookup" do
      applicant.update!(registry_lookup_attempted_at: Time.current)

      expect(presenter.registry_lookup_banner).to be_nil
    end

    {
      "rate_limited" => [ "transient", true ],
      "unavailable" => [ "transient", true ],
      "not_found" => [ "wrong_number", false ],
      "invalid_number" => [ "wrong_number", false ],
      "unauthorized" => [ "unsupported", false ],
      "not_supported" => [ "unsupported", false ],
      "some_new_error" => [ "unsupported", false ]
    }.each do |error, (message_key, retryable)|
      it "maps #{error} to the #{message_key} message#{retryable ? ' with a retry' : ' without an action'}" do
        applicant.update!(registry_lookup_attempted_at: Time.current, registry_lookup_error: error)

        banner = presenter.registry_lookup_banner

        expect(banner.message).to eq(I18n.t("#{scope}.#{message_key}"))
        expect(banner.action_label).to eq(retryable ? I18n.t("#{scope}.retry") : nil)
      end
    end
  end
end
