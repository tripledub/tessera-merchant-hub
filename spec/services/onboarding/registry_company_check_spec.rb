# frozen_string_literal: true

require "rails_helper"

# MH-391: once the chat has the company type, country and number it looks the
# company up and asks the applicant to confirm it is theirs.
RSpec.describe Onboarding::RegistryCompanyCheck do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", company_number: nil, registry_jurisdiction: "gb") }
  let(:company_info) do
    { "company_name" => "Acme Widgets", "company_type" => "limited_company",
      "country_of_incorporation" => "United Kingdom", "registration_number" => "12345678" }
  end
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :company_info,
                                stage_data: { "company_info" => company_info })
  end
  let(:profile) do
    create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED", company_number: "12345678",
                              status: "active")
  end

  def stub_lookup(result)
    allow(Registry::Lookup).to receive(:call).and_return(result)
  end

  def found
    create(:registry_address, registry_profile: profile)
    Registry::Lookup::Result.success(profile)
  end

  describe ".due?" do
    it "is due when a registry-held company has a number, a country with a registry, and nothing has been checked" do
      expect(described_class.due?(session)).to be(true)
    end

    it "is not due for a sole trader or partnership, which no registry holds" do
      %w[sole_trader partnership other].each do |type|
        session.update!(stage_data: { "company_info" => company_info.merge("company_type" => type) })

        expect(described_class.due?(session)).to be(false)
      end
    end

    it "is not due without a registration number" do
      session.update!(stage_data: { "company_info" => company_info.except("registration_number") })

      expect(described_class.due?(session)).to be(false)
    end

    it "is not due for a jurisdiction with no registry client" do
      applicant.update!(registry_jurisdiction: "mt")

      expect(described_class.due?(session)).to be(false)
    end

    it "is not due when the jurisdiction is not known" do
      applicant.update!(registry_jurisdiction: nil)

      expect(described_class.due?(session)).to be(false)
    end

    it "is not due outside the company details stage" do
      session.update!(current_stage: :directors_ubos)

      expect(described_class.due?(session)).to be(false)
    end

    it "is not due again once it has been run, whatever the answer was" do
      stub_lookup(found)
      described_class.run!(session)

      expect(described_class.due?(session)).to be(false)
    end
  end

  describe ".run!" do
    it "looks the number up and waits for the applicant's answer when the company is found" do
      stub_lookup(found)

      expect(described_class.run!(session)).to eq(:found)
      expect(described_class.pending?(session)).to be(true)
      expect(Registry::Lookup).to have_received(:call).with(applicant: applicant, company_number: "12345678",
                                                           jurisdiction: "gb")
    end

    it "records the attempt on the application" do
      stub_lookup(found)

      described_class.run!(session)

      expect(applicant.reload.registry_lookup_attempted_at).to be_present
      expect(applicant.registry_lookup_error).to be_nil
    end

    it "gives up quietly when nothing is found, keeping what the applicant said" do
      stub_lookup(Registry::Lookup::Result.failure(:not_found))

      expect(described_class.run!(session)).to eq(:failed)
      expect(described_class.pending?(session)).to be(false)
      expect(applicant.reload.registry_lookup_error).to eq("not_found")
      expect(session.reload.stage_data["company_info"]).to eq(company_info)
    end

    it "treats a lookup that raises as a failure" do
      allow(Registry::Lookup).to receive(:call).and_raise(Faraday::ConnectionFailed, "down")

      expect(described_class.run!(session)).to eq(:failed)
      expect(applicant.reload.registry_lookup_error).to eq("unavailable")
    end

    it "does not create principals or ownership from the registry" do
      stub_lookup(found)

      expect { described_class.run!(session) }.not_to change { [ KycPrincipal.count, Kyc::OwnershipEdge.count ] }
    end
  end

  describe ".prompt" do
    before do
      stub_lookup(found)
      described_class.run!(session)
    end

    it "states the name, status, registered address and where it came from, then asks" do
      expect(described_class.prompt(session)).to eq(
        "I found **ACME WIDGETS LIMITED**, active, registered at 10 Business Park, Bristol, BS1 1AA " \
        "(Companies House). Is this your company?"
      )
    end
  end

  describe ".confirm!" do
    before do
      stub_lookup(found)
      described_class.run!(session)
    end

    it "saves the registry's name, number and address as the company's" do
      described_class.confirm!(session)

      expect(session.reload.stage_data["company_info"]).to include(
        "company_name" => "ACME WIDGETS LIMITED", "registration_number" => "12345678",
        "registered_address" => "10 Business Park, Bristol, BS1 1AA"
      )
      expect(applicant.reload).to have_attributes(company_name: "ACME WIDGETS LIMITED", company_number: "12345678")
    end

    it "records the registry as the source of the name" do
      described_class.confirm!(session)

      expect(Provenance::CompanyFields.source_for(applicant.reload, "company_name")).to eq(:registry)
    end

    it "is no longer pending, and says what happens next" do
      reply = described_class.confirm!(session)

      expect(described_class.pending?(session)).to be(false)
      expect(reply).to be_a(OnboardingMessage)
      expect(reply.content).to include("Thanks")
    end

    it "opens with the registry's people when the answer finishes the company details (MH-417)" do
      session.update!(stage_data: session.stage_data.merge(
        "company_info" => company_info.merge("registered_address" => "10 Business Park, Bristol, BS1 1AA")
      ))
      create(:registry_director, registry_profile: profile, name: "DOE, Jane")

      reply = described_class.confirm!(session)

      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(reply.content).to include("Thanks, I've saved those details.", "**Jane Doe** as a director")
      expect(reply.content).not_to include("Please provide the first person")
    end

    it "does nothing when nothing is waiting for an answer" do
      described_class.confirm!(session)

      expect { described_class.confirm!(session) }.not_to change(OnboardingMessage, :count)
    end
  end

  describe ".decline!" do
    before do
      stub_lookup(found)
      described_class.run!(session)
    end

    it "keeps what the applicant typed and carries on with the questions" do
      reply = described_class.decline!(session)

      expect(session.reload.stage_data["company_info"]).to eq(company_info)
      expect(applicant.reload.company_name).to eq("Acme Widgets")
      expect(described_class.pending?(session)).to be(false)
      expect(described_class.due?(session)).to be(false)
      expect(reply.content).to include("registered address")
    end
  end
end
