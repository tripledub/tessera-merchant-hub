# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrincipalMatcherService, type: :model do
  let_it_be(:applicant) { create(:applicant) }

  describe ".call" do
    it "delegates to a new instance" do
      result_data = { "full_name" => nil, "date_of_birth" => nil }
      result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

      expect(result).to be_a(described_class::Result)
    end
  end

  describe "#call" do
    context "when full_name is blank" do
      let(:result_data) { { "full_name" => "", "date_of_birth" => nil } }

      it "returns nil principal" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to be_nil
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end

    context "when there is an exact name + DOB match on a passport" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1990-01-15" } }

      it "returns the matching principal with exact method" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
        expect(result.match_confidence).to eq(1.0)
      end
    end

    context "when there is an exact name match (case-insensitive) on a passport" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "john smith", "date_of_birth" => "1990-01-15" } }

      it "matches case-insensitively" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
      end
    end

    context "when the name matches exactly but DOB differs (passport)" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1985-06-20" } }

      it "does not exact-match; falls through to fuzzy" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.match_method).to eq("fuzzy")
      end
    end

    context "when the name matches exactly but DOB differs (driving licence)" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1985-06-20" } }

      it "does not exact-match; falls through to fuzzy (DOB-aware matching applies beyond passports)" do
        result = described_class.call(applicant: applicant, document_type: "driving_licence", result: result_data)

        expect(result.match_method).to eq("fuzzy")
      end
    end

    context "when there is an exact name + DOB match on a driving licence" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1990-01-15" } }

      it "matches exactly, same as a passport would" do
        result = described_class.call(applicant: applicant, document_type: "driving_licence", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
      end
    end

    context "when there is a fuzzy name match above threshold" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Jonathan Smith") }
      let(:result_data) { { "full_name" => "Jonathon Smith", "date_of_birth" => nil } }

      it "returns the principal with fuzzy method and confidence score" do
        result = described_class.call(applicant: applicant, document_type: "utility_bill", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("fuzzy")
        expect(result.match_confidence).to be >= described_class::FUZZY_THRESHOLD
        expect(result.match_confidence).to be <= 1.0
      end
    end

    context "when the extracted name omits middle names" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Andrew Minh-Luan Bui") }
      let(:result_data) { { "full_name" => "Andrew Bui" } }

      it "matches using first and last name fallback" do
        result = described_class.call(applicant: applicant, document_type: "utility_bill", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("fuzzy")
      end
    end

    context "when there is no match and document is a passport" do
      let(:result_data) { { "full_name" => "Completely Unknown Person", "date_of_birth" => "2000-01-01" } }

      it "creates an unconfirmed principal" do
        expect {
          described_class.call(applicant: applicant, document_type: "passport", result: result_data)
        }.to change(applicant.kyc_principals, :count).by(1)
      end

      it "returns the newly created principal with exact method" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal.name).to eq("Completely Unknown Person")
        expect(result.principal.status).to eq("unconfirmed")
        # MH-307: a passport alone is no evidence of a directorship.
        expect(result.principal.role).to eq("unspecified")
        expect(result.match_method).to eq("exact")
        expect(result.match_confidence).to eq(1.0)
      end
    end

    context "when there is no match and document is a utility bill" do
      let(:result_data) { { "full_name" => "No Match Here", "date_of_birth" => nil } }

      it "returns nil principal (does not create one)" do
        expect {
          result = described_class.call(applicant: applicant, document_type: "utility_bill", result: result_data)
          expect(result.principal).to be_nil
          expect(result.match_method).to be_nil
        }.not_to change(KycPrincipal, :count)
      end
    end

    context "when exact name match on non-passport document (no DOB required)" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Doe") }
      let(:result_data) { { "full_name" => "Jane Doe", "date_of_birth" => nil } }

      it "matches by name alone" do
        result = described_class.call(applicant: applicant, document_type: "utility_bill", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
        expect(result.match_confidence).to eq(1.0)
      end
    end

    context "when date_of_birth is invalid" do
      let(:result_data) { { "full_name" => "Some Person", "date_of_birth" => "not-a-date" } }

      it "gracefully handles the invalid date" do
        expect { described_class.call(applicant: applicant, document_type: "passport", result: result_data) }.not_to raise_error
      end
    end

    context "when document_type is driving_licence (a non-passport identity document)" do
      let(:result_data) { { "full_name" => "New Driver", "date_of_birth" => "1995-03-10" } }

      it "does not auto-create a principal (only passports auto-create)" do
        expect {
          described_class.call(applicant: applicant, document_type: "driving_licence", result: result_data)
        }.not_to change(KycPrincipal, :count)
      end
    end

    # MH-303: a registry-fetched principal with only a partial (month/year)
    # date of birth gets cross-checked against a passport's full DOB before
    # the ordinary fuzzy-match behaviour applies.
    context "when a passport agrees with a registry-fetched principal's partial date of birth" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth_month: 3, date_of_birth_year: 1985)
      end
      let(:result_data) { { "full_name" => "Riley Sample", "date_of_birth" => "1985-03-17" } }

      it "links the document to the registry principal" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("registry_corroborated")
        expect(result.dob_mismatch_principal).to be_nil
      end

      it "backfills the principal's full date of birth from the passport" do
        described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(principal.reload.date_of_birth).to eq(Date.new(1985, 3, 17))
      end

      it "does not create a duplicate principal" do
        expect {
          described_class.call(applicant: applicant, document_type: "passport", result: result_data)
        }.not_to change(KycPrincipal, :count)
      end
    end

    context "when a passport disagrees with a registry-fetched principal's partial date of birth" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth_month: 3, date_of_birth_year: 1985)
      end
      let(:result_data) { { "full_name" => "Riley Sample", "date_of_birth" => "1990-06-02" } }

      it "blocks the auto-link and does not create a duplicate principal" do
        result = nil
        expect {
          result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)
        }.not_to change(KycPrincipal, :count)

        expect(result.principal).to be_nil
        expect(result.match_method).to be_nil
        expect(result.dob_mismatch_principal).to eq(principal)
      end

      it "does not change the registry principal's date of birth" do
        described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(principal.reload.date_of_birth).to be_nil
      end
    end

    # Falls back to today's name-only behaviour: with no DOB to compare, the
    # normalized names match exactly (AC7), so this resolves via the
    # ordinary exact-match path rather than the DOB cross-check — either way
    # there's no backfill and no mismatch block.
    context "when a name-matching passport's date of birth is missing" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth_month: 3, date_of_birth_year: 1985)
      end
      let(:result_data) { { "full_name" => "Riley Sample", "date_of_birth" => nil } }

      it "falls back to name-only matching, with no backfill" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
        expect(result.dob_mismatch_principal).to be_nil
        expect(principal.reload.date_of_birth).to be_nil
      end
    end

    context "when a name-matching passport's date of birth is unparseable" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth_month: 3, date_of_birth_year: 1985)
      end
      let(:result_data) { { "full_name" => "Riley Sample", "date_of_birth" => "not-a-date" } }

      it "falls back to name-only matching, with no backfill" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
        expect(principal.reload.date_of_birth).to be_nil
      end
    end

    context "when only fuzzily matching a registry-fetched principal, with the date of birth missing" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth_month: 3, date_of_birth_year: 1985)
      end
      let(:result_data) { { "full_name" => "Riley Sammple", "date_of_birth" => nil } }

      it "matches fuzzily, with no DOB cross-check and no backfill" do
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("fuzzy")
        expect(result.dob_mismatch_principal).to be_nil
        expect(principal.reload.date_of_birth).to be_nil
      end
    end

    context "when a document name-matches a registry-fetched principal in Companies House format (MH-303 AC7)" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "EXAMPLESON, Morgan Lee", source: :registry_fetched) }
      let(:result_data) { { "full_name" => "Morgan Lee Exampleson", "date_of_birth" => nil } }

      it "normalizes the registry name before comparing, and matches" do
        result = described_class.call(applicant: applicant, document_type: "utility_bill", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
      end
    end

    context "when a registry-fetched principal already has a full date of birth" do
      let!(:principal) do
        create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
          date_of_birth: Date.new(1985, 3, 17))
      end

      it "is out of scope for MH-303's DOB cross-check: an exact name+DOB match still wins" do
        result_data = { "full_name" => "Riley Sample", "date_of_birth" => "1985-03-17" }
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
      end

      it "falls through to ordinary fuzzy matching on a differing DOB, not the mismatch-blocking path" do
        result_data = { "full_name" => "Riley Sample", "date_of_birth" => "1999-01-01" }
        result = described_class.call(applicant: applicant, document_type: "passport", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("fuzzy")
        expect(result.dob_mismatch_principal).to be_nil
      end
    end
  end
end
