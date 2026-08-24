# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalsFromRegistry do
  let(:applicant) { create(:applicant) }
  let(:registry_profile) { create(:registry_profile, applicant: applicant) }

  def call
    described_class.call(registry_profile)
  end

  describe ".call" do
    it "creates a principal for an active director" do
      create(:registry_director, registry_profile: registry_profile, name: "DOE, Jane", role: "director", resigned_on: nil)

      expect { call }.to change { applicant.kyc_principals.count }.by(1)

      principal = applicant.kyc_principals.last
      expect(principal.name).to eq("DOE, Jane")
      expect(principal.role).to eq("director")
      expect(principal.source).to eq("registry_fetched")
    end

    it "creates a principal for a corporate-nominee-director" do
      create(:registry_director, registry_profile: registry_profile, name: "Nominee Co Ltd", role: "corporate-nominee-director", resigned_on: nil)

      expect { call }.to change { applicant.kyc_principals.count }.by(1)
      expect(applicant.kyc_principals.last.role).to eq("director")
    end

    it "creates a principal with the secretary role for an active secretary" do
      create(:registry_director, registry_profile: registry_profile, name: "ALDERSON, Anthony Paul", role: "secretary", resigned_on: nil)

      expect { call }.to change { applicant.kyc_principals.count }.by(1)
      expect(applicant.kyc_principals.last.role).to eq("secretary")
    end

    it "creates a principal with the secretary role for a corporate-nominee-secretary" do
      create(:registry_director, registry_profile: registry_profile, name: "SWIFT INCORPORATIONS LIMITED", role: "corporate-nominee-secretary", resigned_on: nil)

      expect { call }.to change { applicant.kyc_principals.count }.by(1)
      expect(applicant.kyc_principals.last.role).to eq("secretary")
    end

    it "does not create a principal for an officer role that is neither director nor secretary" do
      create(:registry_director, registry_profile: registry_profile, name: "Someone Else", role: "llp-member", resigned_on: nil)

      expect { call }.not_to change { applicant.kyc_principals.count }
    end

    it "does not create a principal for a resigned director" do
      create(:registry_director, registry_profile: registry_profile, name: "DOE, Jane", resigned_on: Date.new(2020, 1, 1))

      expect { call }.not_to change { applicant.kyc_principals.count }
    end

    it "does not create principals from persons with significant control (they belong on the Ownership tab, not Principals)" do
      create(:registry_person_with_significant_control,
        registry_profile: registry_profile, name: "Mr Albert Edward Short",
        kind: "individual-person-with-significant-control", ceased_on: nil)

      expect { call }.not_to change { applicant.kyc_principals.count }
    end

    it "does not create a duplicate principal for a name that already exists on the applicant" do
      create(:kyc_principal, applicant: applicant, name: "Jane Doe")
      create(:registry_director, registry_profile: registry_profile, name: "Jane Doe", resigned_on: nil)

      expect { call }.not_to change { applicant.kyc_principals.count }
    end

    it "matches existing names case-insensitively" do
      create(:kyc_principal, applicant: applicant, name: "jane doe")
      create(:registry_director, registry_profile: registry_profile, name: "Jane Doe", resigned_on: nil)

      expect { call }.not_to change { applicant.kyc_principals.count }
    end

    it "is idempotent across repeated calls with the same registry data" do
      create(:registry_director, registry_profile: registry_profile, name: "DOE, Jane", resigned_on: nil)

      call
      expect { call }.not_to change { applicant.kyc_principals.count }
    end
  end
end
