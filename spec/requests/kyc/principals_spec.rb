# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KycPrincipals", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let_it_be(:applicant)  { create(:applicant) }
  let_it_be(:principal)  { create(:kyc_principal, applicant: applicant) }

  describe "GET /applicants/:applicant_id/kyc_principals/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get new_applicant_kyc_principal_path(applicant)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_applicant_kyc_principal_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/:applicant_id/kyc_principals" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates principal and redirects to applicant" do
        post applicant_kyc_principals_path(applicant), params: {
          kyc_principal: { name: "Jane Smith", role: "director" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(applicant.kyc_principals.find_by(name: "Jane Smith")).to be_present
      end

      it "re-renders new with 422 on missing name" do
        post applicant_kyc_principals_path(applicant), params: {
          kyc_principal: { name: "", role: "director" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_principals_path(applicant), params: {
          kyc_principal: { name: "X", role: "director" }
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # MH-307: staff pick a real role here; "unspecified" is only ever set by
  # the passport auto-creation path, never a deliberate human choice.
  describe "GET /applicants/:applicant_id/kyc_principals/new — role options" do
    before { sign_in psp_admin }

    it "does not offer unspecified as a selectable role" do
      get new_applicant_kyc_principal_path(applicant)

      select = Nokogiri::HTML(response.body).at_css("select[name='kyc_principal[role]']")
      expect(select.css("option").map { |o| o["value"] }).not_to include("unspecified")
    end
  end

  describe "GET /applicants/:id — an unspecified-role principal" do
    let_it_be(:unspecified_principal) { create(:kyc_principal, applicant: applicant, role: :unspecified) }

    before { sign_in psp_admin }

    it "shows the unspecified label, not a blank or director role" do
      get applicant_path(applicant)

      expect(response.body).to include(I18n.t("applicants.show.principals.roles.unspecified"))
    end
  end

  describe "GET /kyc_principals/:id — linked documents table" do
    before { sign_in psp_admin }

    it "renders each document's type, so the search box can filter by it (MH-329)" do
      document = create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)

      get kyc_principal_path(principal)

      row = Nokogiri::HTML::DocumentFragment.parse(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(document)}")
      expect(row.text).to include(I18n.t("kyc.documents.document_types.passport"))
      expect(response.body).to include(I18n.t("kyc.principals.show.documents.table.type"))
    end
  end

  describe "GET /kyc_principals/:id/edit" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get edit_kyc_principal_path(principal)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get edit_kyc_principal_path(principal)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /kyc_principals/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "updates and redirects to applicant" do
        patch kyc_principal_path(principal), params: {
          kyc_principal: { name: "Updated Name", role: "psc" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(principal.reload.name).to eq("Updated Name")
      end
    end
  end

  describe "DELETE /kyc_principals/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "destroys and redirects to applicant" do
        to_delete = create(:kyc_principal, applicant: applicant)
        delete kyc_principal_path(to_delete)
        expect(response).to redirect_to(applicant_path(applicant))
        expect(KycPrincipal.find_by(id: to_delete.id)).to be_nil
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_principal_path(principal)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
