# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::SavePrincipals do
  let(:application) do
    create(
      :onboarding_application,
      current_step: "principals",
      completed_steps: %w[company fulfilment currencies processing payments descriptor volumes countries]
    )
  end

  let(:attributes) do
    {
      applicant_attributes: {
        id: application.applicant_id,
        kyc_principals_attributes: {
          "0" => {
            name: "Alex Director",
            date_of_birth: "1980-01-02",
            email: "alex@example.com",
            role: "director"
          },
          "1" => {
            name: "Morgan Owner",
            date_of_birth: "1975-03-04",
            email: "morgan@example.com",
            role: "psc",
            ownership_percentage: "62.50"
          }
        }
      }
    }
  end

  it "saves applicant-declared directors and owners and advances" do
    expect(described_class.call(application: application, attributes: attributes)).to be true

    expect(application.reload).to have_attributes(current_step: "review")
    expect(application.applicant.kyc_principals.pluck(:name, :source)).to contain_exactly(
      [ "Alex Director", "applicant_declared" ],
      [ "Morgan Owner", "applicant_declared" ]
    )
    expect(application.applicant.kyc_principals.find_by(name: "Morgan Owner").ownership_percentage).to eq(62.5)
  end

  it "does not persist an owner without an ownership percentage" do
    attributes[:applicant_attributes][:kyc_principals_attributes]["1"][:ownership_percentage] = ""

    expect(described_class.call(application: application, attributes: attributes)).to be false
    expect(application.reload.current_step).to eq("principals")
    expect(application.applicant.kyc_principals.reload).to be_empty
  end

  it "rejects a save before the principals step is reached" do
    application.update!(current_step: "countries", completed_steps: application.completed_steps - [ "countries" ])

    expect do
      described_class.call(application: application, attributes: attributes)
    end.to raise_error(OnboardingApplications::Advance::StepConflict)

    expect(application.applicant.kyc_principals.reload).to be_empty
  end

  it "updates and removes people while revisiting without moving backwards" do
    principal = create_declared_principal(email: "principal@example.com")
    retained = create_declared_principal(email: "retained@example.com")
    application.update!(current_step: "review", completed_steps: application.completed_steps + [ "principals" ])
    revisit = {
      applicant_attributes: {
        id: application.applicant_id,
        kyc_principals_attributes: {
          "0" => { id: principal.id, _destroy: "1" },
          "1" => { id: retained.id, name: "Updated Person", date_of_birth: "1985-05-06",
                    email: "retained@example.com", role: "director" }
        }
      }
    }

    expect(described_class.call(application: application, attributes: revisit)).to be true
    expect(application.reload.current_step).to eq("review")
    expect(application.applicant.kyc_principals.reload.pluck(:name)).to eq([ "Updated Person" ])
  end

  def create_declared_principal(email:)
    create(
      :kyc_principal,
      applicant: application.applicant,
      source: :applicant_declared,
      date_of_birth: Date.new(1985, 5, 6),
      email: email
    )
  end
end
