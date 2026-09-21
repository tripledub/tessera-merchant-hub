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

    it "summarizes applicant policy requirements when there are no entities" do
      applicant.update!(sector: :crypto_exchange)
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      expect(presenter.entity_summary).to eq("2 policy requirements evaluated")
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

    it "uses the policy title when an applicant-level result has no entity" do
      applicant.update!(sector: :crypto_exchange)
      assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
      presenter = described_class.new(assessment, template)

      expect(presenter.missing_summary).to include(
        "VASP registration: Vasp registration",
        "Wallet and custody infrastructure attestation: Wallet custody infrastructure attestation"
      )
    end
  end

  # MH-200: fixes the MH-198-flagged gap where a confirmation_required result
  # rendered with the same red "Not Compliant" treatment as an outright
  # rejection, with no detail at all (missing_summary only ever looked at
  # unmet_results).
  describe "confirmation_required handling" do
    before do
      I18n.backend.store_translations(
        :en,
        kyc: { policy_requirements: { test: { optional_policy: {
          title: "Optional policy",
          guidance: "Upload the optional policy when available."
        } } } }
      )
    end

    after do
      I18n.backend.reload!
    end

    let(:warning_requirement) do
      Kyc::PolicyRequirement.new(
        id: "test.optional_policy",
        rule: "required_document",
        outcome: "warning",
        source: "test",
        parameters: { "document_type" => "aml_ctf_policy", "subject" => "applicant" }
      )
    end

    def stub_confirmation_required_rule!
      stub_const("AwaitingRule", Class.new(Kyc::Compliance::BaseRule) {
        def applies_to?(_entity)
          true
        end

        def evaluate(entity)
          build_result(
            entity: entity,
            requirements: [ "passport" ],
            satisfied: [],
            awaiting_confirmation: [ "passport" ]
          )
        end
      })
    end

    describe "#overall_status_badge" do
      it "returns an amber 'Awaiting Review' badge when only confirmation_required results block" do
        stub_confirmation_required_rule!
        entity # ensure created
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        presenter = described_class.new(assessment, template)

        html = presenter.overall_status_badge
        expect(html).to include("Awaiting Review")
        expect(html).to include("bg-amber-50")
      end

      it "remains amber when a non-blocking warning is unmet" do
        allow(Kyc::EffectivePolicy).to receive(:for).with(applicant).and_return([ warning_requirement ])
        stub_confirmation_required_rule!
        entity
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        presenter = described_class.new(assessment, template)

        expect(assessment.unmet_results).to contain_exactly(
          an_object_having_attributes(outcome: "warning", status: :unmet)
        )
        expect(assessment.confirmation_required_results).to contain_exactly(
          an_object_having_attributes(outcome: :blocking, status: :confirmation_required)
        )
        expect(presenter.overall_status_badge).to include("Awaiting Review", "bg-amber-50")
        expect(presenter.overall_status_container_class).to include("border-amber-500")
      end
    end

    describe "#overall_status_container_class" do
      it "returns an amber container class distinct from compliant/not-compliant" do
        stub_confirmation_required_rule!
        entity
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        presenter = described_class.new(assessment, template)

        expect(presenter.overall_status_container_class).to include("border-amber-500")
      end
    end

    describe "#awaiting_confirmation_summary" do
      it "lists confirmation_required items distinctly from unmet items" do
        stub_confirmation_required_rule!
        entity
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        presenter = described_class.new(assessment, template)

        summary = presenter.awaiting_confirmation_summary
        expect(summary).to be_an(Array)
        expect(summary.first).to include(entity.name)
        expect(summary.first).to include("Passport")
        expect(presenter.missing_summary).to be_nil
      end

      it "returns nil when nothing is awaiting confirmation" do
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
        entity
        assessment = Kyc::Compliance::ReadinessAssessment.for(applicant)
        presenter = described_class.new(assessment, template)

        expect(presenter.awaiting_confirmation_summary).to be_nil
      end

      it "uses the policy title when an applicant-level result has no entity" do
        result = Kyc::Compliance::RuleResult.new(
          rule_name: "Required document",
          entity: nil,
          status: :confirmation_required,
          requirements: [ "aml_ctf_policy" ],
          satisfied: [],
          missing: [],
          awaiting_confirmation: [ "aml_ctf_policy" ],
          title: "AML/CTF policy"
        )
        assessment = instance_double(
          Kyc::Compliance::ReadinessAssessment,
          confirmation_required_results: [ result ]
        )
        presenter = described_class.new(assessment, template)

        expect(presenter.awaiting_confirmation_summary).to eq([ "AML/CTF policy: Aml ctf policy" ])
      end
    end
  end

  # MH-251: readiness has four outcomes, each with its own badge, container and
  # explanation, shared with the Summary tab and the executive summary PDF.
  describe "readiness outcomes (MH-251)" do
    let(:staff) { create(:user, :psp_admin) }

    def presenter_for(applicant)
      described_class.new(Kyc::Compliance::ReadinessAssessment.for(applicant.reload), template)
    end

    context "when no ownership is captured and nobody has attested" do
      subject(:presenter) { presenter_for(applicant) }

      it "shows a neutral 'Not Assessable' badge and container" do
        expect(presenter.overall_status_badge).to include("Not Assessable", "bg-gray-100")
        expect(presenter.overall_status_container_class).to include("border-gray-300")
      end

      it "explains why readiness cannot be assessed" do
        expect(presenter.outcome_message).to include("No ownership has been captured")
      end

      it "offers the attestation and shows no attestation summary" do
        expect(presenter).to be_attestation_available
        expect(presenter.attestation_summary).to be_nil
      end
    end

    context "when staff attested there are no corporate owners" do
      subject(:presenter) do
        applicant.attest_no_corporate_owners!(by: staff)
        presenter_for(applicant)
      end

      it "is compliant, with who and when in the attestation summary" do
        expect(presenter.overall_status_badge).to include("Compliant", "bg-green-50")
        expect(presenter.attestation_summary).to include(staff.email, Time.current.strftime("%-d %b %Y"))
      end

      it "no longer offers the attestation, but offers to remove it" do
        expect(presenter).not_to be_attestation_available
        expect(presenter).to be_attestation_revocable
      end
    end

    it "only offers the attestation while there are no ownership entities" do
      entity

      expect(presenter_for(applicant)).not_to be_attestation_available
    end

    it "keeps the amber 'Awaiting Review' treatment for :requires_review" do
      entity
      create(:kyc_validation_warning, applicant: applicant, kyc_document: nil, corporate_entity: nil,
                                      warning_type: :unresolved_chain, message: "Unresolved ownership chain: Test Corp")

      presenter = presenter_for(applicant)

      expect(presenter.overall_status_badge).to include("Awaiting Review", "bg-amber-50")
      expect(presenter.overall_status_container_class).to include("border-amber-500")
      expect(presenter.outcome_message).to include("staff review")
    end

    it "shows a red 'Not Compliant' outcome for an uncaptured UBO and lists what is missing" do
      applicant.attest_no_corporate_owners!(by: staff)
      create(:kyc_validation_warning, applicant: applicant, kyc_document: nil, corporate_entity: nil,
                                      warning_type: :ubo_threshold_exceeded, message: "UBO identified",
                                      metadata: { individual_name: "Test Person" })

      presenter = presenter_for(applicant)

      expect(presenter.overall_status_badge).to include("Not Compliant", "bg-red-50")
      expect(presenter.missing_summary).to eq([ "UBO Test Person: Ownership entity" ])
    end
  end
end
