# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ComplianceReadinessPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate) }

  before do
    Kyc::Compliance::RuleRegistry.reset!
  end

  describe "#overall_status_badge" do
    it "returns green badge when compliant" do
      stub_const("AllMetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation" ],
            satisfied: [ "certificate_of_incorporation" ]
          )
        end
      })

      entity # ensure created
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      html = presenter.overall_status_badge
      expect(html).to include("Compliant")
      expect(html).to include("bg-green-50")
    end

    it "returns red badge when not compliant" do
      stub_const("UnmetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation" ],
            satisfied: []
          )
        end
      })

      entity # ensure created
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      html = presenter.overall_status_badge
      expect(html).to include("Not Compliant")
      expect(html).to include("bg-red-50")
    end
  end

  describe "#entity_summary" do
    it "returns formatted summary" do
      stub_const("AllMetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation" ],
            satisfied: [ "certificate_of_incorporation" ]
          )
        end
      })

      entity # ensure created
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      expect(presenter.entity_summary).to eq("1 of 1 entities compliant")
    end
  end

  describe "#missing_summary" do
    it "groups missing items by entity name" do
      stub_const("UnmetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation", "articles_of_association" ],
            satisfied: []
          )
        end
      })

      entity # ensure created
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      summary = presenter.missing_summary
      expect(summary).to be_an(Array)
      expect(summary.first).to include(entity.name)
      expect(summary.first).to include("Certificate of incorporation")
    end

    it "returns nil when everything is met" do
      stub_const("AllMetRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "certificate_of_incorporation" ],
            satisfied: [ "certificate_of_incorporation" ]
          )
        end
      })

      entity # ensure created
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      expect(presenter.missing_summary).to be_nil
    end
  end
end
