# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::DomainBlocklistEntries", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }

  describe "GET /admin/domain_blocklist_entries" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "lists each entry with who added it" do
        create(:domain_blocklist_entry, name: "godaddy.com", created_by: psp_admin)
        create(:domain_blocklist_entry, name: "namecheap.com", created_by: nil)

        get admin_domain_blocklist_entries_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("godaddy.com", "namecheap.com", psp_admin.email)
      end

      it "explains what the list does" do
        get admin_domain_blocklist_entries_path

        expect(response.body).to include("automatically rejected")
        expect(response.body).to include("Existing domains are not changed")
      end

      it "says so when the list is empty" do
        get admin_domain_blocklist_entries_path

        expect(response.body).to include("No domains are blocked yet")
      end

      it "offers a form to add a domain" do
        get admin_domain_blocklist_entries_path

        expect(response.body).to include("domain_blocklist_entry[name]")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get admin_domain_blocklist_entries_path

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get admin_domain_blocklist_entries_path

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /admin/domain_blocklist_entries" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "adds the domain, records who added it, and redirects to the list" do
        post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: "godaddy.com" } }

        expect(response).to redirect_to(admin_domain_blocklist_entries_path)
        entry = DomainBlocklistEntry.find_by!(name: "godaddy.com")
        expect(entry.created_by).to eq(psp_admin)
      end

      it "reduces a pasted URL to the registrable domain" do
        post admin_domain_blocklist_entries_path,
          params: { domain_blocklist_entry: { name: "https://www.GoDaddy.com/domains" } }

        expect(DomainBlocklistEntry.pluck(:name)).to eq([ "godaddy.com" ])
      end

      it "refuses a subdomain: 422, nothing added, the reason and the input shown again" do
        expect {
          post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: "mail.godaddy.com" } }
        }.not_to change(DomainBlocklistEntry, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("mail.godaddy.com")
        expect(response.body).to include("registrable domain")
      end

      it "refuses a blank name" do
        expect {
          post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: " " } }
        }.not_to change(DomainBlocklistEntry, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a duplicate" do
        create(:domain_blocklist_entry, name: "godaddy.com")

        expect {
          post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: "GoDaddy.com" } }
        }.not_to change(DomainBlocklistEntry, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "leaves domains applicants already have alone" do
        existing = create(:applicant_domain, name: "godaddy.com", review_status: :pending)

        post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: "godaddy.com" } }

        expect(existing.reload).to be_pending
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and adds nothing" do
        expect {
          post admin_domain_blocklist_entries_path, params: { domain_blocklist_entry: { name: "godaddy.com" } }
        }.not_to change(DomainBlocklistEntry, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /admin/domain_blocklist_entries/:id" do
    let!(:entry) { create(:domain_blocklist_entry, name: "godaddy.com") }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "removes the entry and redirects to the list" do
        delete admin_domain_blocklist_entry_path(entry)

        expect(response).to redirect_to(admin_domain_blocklist_entries_path)
        expect(DomainBlocklistEntry.exists?(entry.id)).to be(false)
      end

      it "leaves domains already rejected by the blocklist alone" do
        rejected = create(:applicant_domain, name: "godaddy.com", review_status: :rejected, rejection_reason: :blocklisted)

        delete admin_domain_blocklist_entry_path(entry)

        expect(rejected.reload).to be_rejected_as_blocklisted
      end

      it "returns 404 for an unknown entry" do
        delete admin_domain_blocklist_entry_path(id: 0)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and keeps the entry" do
        delete admin_domain_blocklist_entry_path(entry)

        expect(response).to have_http_status(:forbidden)
        expect(DomainBlocklistEntry.exists?(entry.id)).to be(true)
      end
    end
  end

  describe "navigation" do
    it "shows a psp_admin the Domain blocklist link" do
      sign_in psp_admin

      get applicants_path

      expect(response.body).to include(admin_domain_blocklist_entries_path)
    end

    it "does not show it to a psp_support user" do
      sign_in psp_support

      get applicants_path

      expect(response.body).not_to include(admin_domain_blocklist_entries_path)
    end
  end
end
