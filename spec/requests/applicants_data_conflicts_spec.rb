# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applicant overview data conflicts (MH-389)", type: :request do
  let(:psp_admin) { create(:user, :psp_admin) }
  let(:applicant) { create(:applicant, name: "Acme Corp", company_name: "Acme Widgets Ltd") }

  before { sign_in psp_admin }

  it "lists open conflicts with both values and their sources, read-only" do
    applicant.data_conflicts.create!(
      record_type: "Applicant", record_id: applicant.id, field: "company_name",
      held_value: "ACME WIDGETS LIMITED", held_source: :registry, held_provider: "companies_house",
      proposed_value: "Acme Widgets Ltd", proposed_source: :applicant_declared, detected_at: Time.current
    )

    get applicant_path(applicant)

    expect(response.body).to include("data-testid=\"data-conflicts\"")
    expect(response.body).to include("ACME WIDGETS LIMITED", "Acme Widgets Ltd", "Registry (companies_house)")
    expect(response.body).not_to include("Resolve")
  end

  it "shows nothing about conflicts when there are none" do
    get applicant_path(applicant)

    expect(response.body).not_to include("data-testid=\"data-conflicts\"")
  end

  it "shows where the company name came from" do
    Provenance::CompanyFields.apply!(applicant: applicant, field: "company_name", value: "Acme Widgets Ltd",
                                     source: :registry, provider: "companies_house")

    get applicant_path(applicant)

    expect(response.body).to include("data-testid=\"fact-source\"")
    expect(response.body).to include("(Registry (companies_house))")
  end
end
