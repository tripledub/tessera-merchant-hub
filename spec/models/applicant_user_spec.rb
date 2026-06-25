# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantUser, type: :model do
  subject(:applicant_user) { build(:applicant_user) }

  it "is valid with valid attributes" do
    expect(applicant_user).to be_valid
  end

  it "requires an email" do
    applicant_user.email = nil
    expect(applicant_user).not_to be_valid
  end

  it "requires a password" do
    applicant_user.password = nil
    expect(applicant_user).not_to be_valid
  end

  it "belongs to an applicant" do
    expect(applicant_user.applicant).to be_an(Applicant)
  end
end
