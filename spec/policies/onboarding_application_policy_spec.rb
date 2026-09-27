# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplicationPolicy do
  %i[show? update?].each do |query|
    it "allows a confirmed member of the applicant" do
      applicant_user = create(:applicant_user)
      application = create(:onboarding_application, applicant: applicant_user.applicant)

      expect(described_class.new(applicant_user, application).public_send(query)).to be(true)
    end

    it "denies a user belonging to another applicant" do
      applicant_user = create(:applicant_user)
      application = create(:onboarding_application)

      expect(described_class.new(applicant_user, application).public_send(query)).to be(false)
    end

    it "denies an unconfirmed applicant user" do
      applicant_user = create(:applicant_user, :unconfirmed)
      application = create(:onboarding_application, applicant: applicant_user.applicant)

      expect(described_class.new(applicant_user, application).public_send(query)).to be(false)
    end
  end
end
