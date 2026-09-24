# frozen_string_literal: true

require "rails_helper"

# MH-331: manual "these two principal rows are the same person" merge.
RSpec.describe "Kyc::PrincipalMerges", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let_it_be(:applicant) { create(:applicant) }

  describe "GET /kyc_principals/:principal_id/merge/new" do
    let_it_be(:survivor) { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }
    let_it_be(:other_applicant_principal) { create(:kyc_principal) }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "lists other principals for the same applicant as merge candidates" do
        candidate = create(:kyc_principal, applicant: applicant, name: "J Smith")

        get new_kyc_principal_merge_path(survivor)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(candidate.name)
        expect(response.body).not_to include(other_applicant_principal.name)
      end

      it "excludes an already-merged-away principal from the candidate list" do
        already_merged = create(:kyc_principal, applicant: applicant, name: "Merged Away")
        another_survivor = create(:kyc_principal, applicant: applicant, name: "Another Survivor")
        already_merged.update!(merged_into: another_survivor)

        get new_kyc_principal_merge_path(survivor)

        expect(response.body).not_to include("Merged Away")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_kyc_principal_merge_path(survivor)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc_principals/:principal_id/merge" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "backfills only the survivor's blank fields, never overwriting an existing value" do
        survivor = create(:kyc_principal, applicant: applicant, name: "Jane Smith",
          email: "jane@example.com", date_of_birth: nil, role: :unspecified)
        loser = create(:kyc_principal, applicant: applicant, name: "J Smith",
          email: "duplicate@example.com", date_of_birth: Date.new(1990, 1, 1), role: :director)

        post kyc_principal_merge_path(survivor), params: { loser_id: loser.id }

        survivor.reload
        expect(survivor.email).to eq("jane@example.com")
        expect(survivor.date_of_birth).to eq(Date.new(1990, 1, 1))
        expect(survivor.role).to eq("director")
      end

      it "re-points the loser's documents onto the survivor and soft-deletes the loser" do
        survivor = create(:kyc_principal, applicant: applicant)
        loser = create(:kyc_principal, applicant: applicant)
        document = create(:kyc_document, applicant: applicant, kyc_principal: loser)

        post kyc_principal_merge_path(survivor), params: { loser_id: loser.id }

        expect(document.reload.kyc_principal).to eq(survivor)
        expect(loser.reload.merged_into).to eq(survivor)
        expect(loser.reload.merged?).to be true
      end

      it "redirects to the survivor on success" do
        survivor = create(:kyc_principal, applicant: applicant)
        loser = create(:kyc_principal, applicant: applicant)

        post kyc_principal_merge_path(survivor), params: { loser_id: loser.id }

        expect(response).to redirect_to(kyc_principal_path(survivor))
      end

      it "rejects merging a principal from a different applicant (not offered as a candidate)" do
        survivor = create(:kyc_principal, applicant: applicant)
        other_principal = create(:kyc_principal)

        post kyc_principal_merge_path(survivor), params: { loser_id: other_principal.id }

        expect(response).to have_http_status(:not_found)
        expect(other_principal.reload.merged?).to be false
      end

      it "rejects merging an already-merged-away principal (not offered as a candidate)" do
        survivor = create(:kyc_principal, applicant: applicant)
        another_survivor = create(:kyc_principal, applicant: applicant)
        already_merged = create(:kyc_principal, applicant: applicant, merged_into: another_survivor)

        post kyc_principal_merge_path(survivor), params: { loser_id: already_merged.id }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        survivor = create(:kyc_principal, applicant: applicant)
        loser = create(:kyc_principal, applicant: applicant)

        post kyc_principal_merge_path(survivor), params: { loser_id: loser.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
