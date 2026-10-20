# frozen_string_literal: true

require "rails_helper"

RSpec.describe RegistryRecheckJob do
  it "re-checks the applicant against the registry" do
    applicant = create(:applicant)
    allow(Provenance::RegistryRecheck).to receive(:call)

    described_class.perform_now(applicant.id)

    expect(Provenance::RegistryRecheck).to have_received(:call).with(applicant)
  end

  it "does nothing when the applicant no longer exists" do
    allow(Provenance::RegistryRecheck).to receive(:call)

    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
    expect(Provenance::RegistryRecheck).not_to have_received(:call)
  end
end
