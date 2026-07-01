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
        expect(result.principal.role).to eq("director")
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
  end
end
