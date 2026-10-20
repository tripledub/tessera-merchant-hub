# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provenance::RegistryRecheck do
  let(:fake_client_class) { Class.new(Registry::Client) }
  let(:fake_client) { instance_double(fake_client_class) }
  let(:applicant) do
    create(:applicant, registry_jurisdiction: "gb", company_number: "12345678", company_name: "Acme Widgets Ltd")
  end

  before do
    stub_const("Registry::Lookup::CLIENTS", { "gb" => fake_client_class })
    allow(fake_client_class).to receive(:new).and_return(fake_client)
  end

  def registry_returns(name:)
    allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(
      Registry::FetchResult.success(company_name: name, status: "active", incorporated_on: Date.new(2020, 1, 1),
                                    directors: [], addresses: [], people_with_significant_control: [])
    )
  end

  it "records a conflict when the registry name differs, without overwriting the applicant's value" do
    registry_returns(name: "ACME WIDGETS LIMITED")

    expect(described_class.call(applicant)).to eq(:checked)

    expect(applicant.reload.company_name).to eq("Acme Widgets Ltd")
    expect(applicant.data_conflicts.status_open.first).to have_attributes(
      field: "company_name", held_value: "Acme Widgets Ltd", proposed_value: "ACME WIDGETS LIMITED",
      proposed_source: "registry", proposed_provider: "companies_house"
    )
  end

  it "records nothing when the registry agrees" do
    registry_returns(name: "Acme Widgets Ltd")

    described_class.call(applicant)

    expect(applicant.data_conflicts).to be_empty
  end

  it "records the attempt on the applicant" do
    registry_returns(name: "Acme Widgets Ltd")

    freeze_time do
      described_class.call(applicant)

      expect(applicant.reload).to have_attributes(registry_lookup_attempted_at: Time.current, registry_lookup_error: nil)
    end
  end

  it "records the error and raises nothing when the registry is unreachable" do
    allow(fake_client).to receive(:fetch).and_return(Registry::FetchResult.failure(error_type: :unavailable))

    expect(described_class.call(applicant)).to eq(:failed)

    expect(applicant.reload.registry_lookup_error).to eq("unavailable")
    expect(applicant.data_conflicts).to be_empty
  end

  it "skips applicants with no company number" do
    applicant.update!(company_number: nil)

    expect(described_class.call(applicant)).to eq(:skipped)
    expect(fake_client_class).not_to have_received(:new)
  end

  it "skips applicants whose jurisdiction has no registry client" do
    applicant.update!(registry_jurisdiction: nil)

    expect(described_class.call(applicant)).to eq(:skipped)
    expect(fake_client_class).not_to have_received(:new)
  end
end
