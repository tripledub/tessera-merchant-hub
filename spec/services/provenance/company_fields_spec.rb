# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provenance::CompanyFields do
  let(:applicant) { create(:applicant, company_name: nil, company_number: nil) }
  let(:fetched_at) { Time.zone.local(2026, 10, 1, 9, 0, 0) }

  def provenance(field) = DataProvenance.find_by(record_type: "Applicant", record_id: applicant.id, field: field)

  def open_conflicts = applicant.data_conflicts.status_open

  def apply_registry(value, field: "company_name")
    described_class.apply!(applicant: applicant, field: field, value: value, source: :registry,
                           provider: "companies_house", retrieved_at: fetched_at)
  end

  def apply_applicant(value, field: "company_name")
    described_class.apply!(applicant: applicant, field: field, value: value, source: :applicant_declared)
  end

  describe ".source_for" do
    it "treats data with no recorded provenance as applicant-declared" do
      expect(described_class.source_for(applicant, "company_name")).to eq(:applicant_declared)
    end
  end

  describe ".apply!" do
    it "stores an applicant's value on an empty field with applicant provenance and no conflict" do
      apply_applicant("Acme Widgets Ltd")

      expect(applicant.reload.company_name).to eq("Acme Widgets Ltd")
      expect(provenance("company_name")).to have_attributes(source: "applicant_declared")
      expect(open_conflicts).to be_empty
    end

    it "ignores blank values" do
      applicant.update!(company_name: "Acme Widgets Ltd")

      apply_applicant("  ")

      expect(applicant.reload.company_name).to eq("Acme Widgets Ltd")
      expect(DataProvenance.count).to eq(0)
    end

    context "when the registry replaces an applicant-declared value" do
      before { apply_applicant("Acme Widgets") }

      it "saves the registry value, keeps the previous one for audit and records registry provenance" do
        apply_registry("ACME WIDGETS LIMITED")

        expect(applicant.reload.company_name).to eq("ACME WIDGETS LIMITED")
        expect(provenance("company_name")).to have_attributes(
          source: "registry", provider: "companies_house", retrieved_at: fetched_at, previous_value: "Acme Widgets"
        )
        expect(open_conflicts).to be_empty
      end
    end

    context "when the applicant changes a registry-sourced value" do
      before { apply_registry("ACME WIDGETS LIMITED") }

      it "saves the applicant's value, marks it applicant-declared and records one open conflict" do
        apply_applicant("Acme Widgets Ltd")

        expect(applicant.reload.company_name).to eq("Acme Widgets Ltd")
        expect(provenance("company_name")).to have_attributes(source: "applicant_declared",
                                                              previous_value: "ACME WIDGETS LIMITED")
        expect(open_conflicts.count).to eq(1)
        expect(open_conflicts.first).to have_attributes(
          field: "company_name", held_value: "ACME WIDGETS LIMITED", held_source: "registry",
          held_provider: "companies_house", proposed_value: "Acme Widgets Ltd", proposed_source: "applicant_declared"
        )
      end

      it "updates the open conflict on a further edit instead of adding another" do
        apply_applicant("Acme Widgets Ltd")
        apply_applicant("Acme Widgets Trading Ltd")

        expect(open_conflicts.count).to eq(1)
        expect(open_conflicts.first).to have_attributes(proposed_value: "Acme Widgets Trading Ltd",
                                                        held_value: "ACME WIDGETS LIMITED", held_source: "registry")
      end

      it "does not downgrade the provenance when the applicant re-enters the same value" do
        apply_applicant("ACME WIDGETS LIMITED")

        expect(provenance("company_name")).to have_attributes(source: "registry")
        expect(open_conflicts).to be_empty
      end
    end

    it "upgrades the provenance when the registry confirms an applicant's value" do
      apply_applicant("12345678", field: "company_number")

      apply_registry("12345678", field: "company_number")

      expect(provenance("company_number")).to have_attributes(source: "registry", provider: "companies_house")
      expect(open_conflicts).to be_empty
    end

    it "closes an open conflict once the registry value is back in place" do
      apply_registry("ACME WIDGETS LIMITED")
      apply_applicant("Acme Widgets Ltd")

      apply_registry("ACME WIDGETS LIMITED")

      expect(open_conflicts).to be_empty
      expect(applicant.data_conflicts.status_resolved.count).to eq(1)
    end

    it "keeps staff-verified values above everything a lower source later supplies" do
      DataProvenance.create!(applicant: applicant, record_type: "Applicant", record_id: applicant.id,
                             field: "company_name", source: :staff_verified)
      applicant.update!(company_name: "Verified Name Ltd")

      apply_registry("Registry Name Ltd")

      expect(applicant.reload.company_name).to eq("Registry Name Ltd")
      expect(provenance("company_name").source).to eq("registry")
      expect(open_conflicts.first).to have_attributes(held_source: "staff_verified", proposed_source: "registry")
    end
  end

  describe ".record_applicant_edit!" do
    it "records a conflict when a value already saved by the form replaced a registry value" do
      apply_registry("ACME WIDGETS LIMITED")
      applicant.update!(company_name: "Acme Widgets Ltd")

      described_class.record_applicant_edit!(applicant: applicant, field: "company_name",
                                             previous_value: "ACME WIDGETS LIMITED")

      expect(provenance("company_name")).to have_attributes(source: "applicant_declared")
      expect(open_conflicts.first).to have_attributes(held_value: "ACME WIDGETS LIMITED",
                                                      proposed_value: "Acme Widgets Ltd")
    end
  end

  describe ".flag_difference!" do
    before { apply_applicant("Acme Widgets Ltd") }

    it "records a conflict without changing the stored value or its provenance" do
      described_class.flag_difference!(applicant: applicant, field: "company_name",
                                       registry_value: "ACME WIDGETS LIMITED", provider: "companies_house")

      expect(applicant.reload.company_name).to eq("Acme Widgets Ltd")
      expect(provenance("company_name").source).to eq("applicant_declared")
      expect(open_conflicts.first).to have_attributes(
        held_value: "Acme Widgets Ltd", held_source: "applicant_declared",
        proposed_value: "ACME WIDGETS LIMITED", proposed_source: "registry", proposed_provider: "companies_house"
      )
    end

    it "records nothing when the registry agrees" do
      described_class.flag_difference!(applicant: applicant, field: "company_name",
                                       registry_value: "Acme Widgets Ltd", provider: "companies_house")

      expect(open_conflicts).to be_empty
    end

    it "does not duplicate an existing open conflict" do
      2.times do
        described_class.flag_difference!(applicant: applicant, field: "company_name",
                                         registry_value: "ACME WIDGETS LIMITED", provider: "companies_house")
      end

      expect(open_conflicts.count).to eq(1)
    end
  end
end
