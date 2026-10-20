# frozen_string_literal: true

require "rails_helper"

# MH-405: which screen a refresh of the enter-code page shows, worked out from
# the latest code row for the applicant and address.
RSpec.describe ApplicantSignInCodes::Status do
  let(:applicant) { create(:applicant) }
  let(:email) { "invitee@example.com" }

  def status
    described_class.call(applicant: applicant, email: email)
  end

  it "is :none when no code was ever sent" do
    expect(status).to have_attributes(state: :none, resend_in: 0)
  end

  it "is :active for a fresh code, with the seconds until another may be sent" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, created_at: 10.seconds.ago)

    expect(status.state).to eq(:active)
    expect(status.resend_in).to be_between(19, 20)
  end

  it "has no wait once the minimum gap has passed" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, created_at: 2.minutes.ago)

    expect(status).to have_attributes(state: :active, resend_in: 0)
  end

  it "is :expired once the code's lifetime has passed" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, created_at: 11.minutes.ago, expires_at: 1.minute.ago)

    expect(status.state).to eq(:expired)
  end

  it "is :used for a code that was accepted" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, consumed_at: 1.minute.ago)

    expect(status.state).to eq(:used)
  end

  it "is :locked after five wrong attempts, or when the code was invalidated" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, attempts: 5)
    expect(status.state).to eq(:locked)

    ApplicantSignInCode.delete_all
    create(:applicant_sign_in_code, applicant: applicant, email: email, invalidated_at: 1.minute.ago)
    expect(status.state).to eq(:locked)
  end

  it "only looks at the latest code, so an older locked one does not hide a fresh one" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, attempts: 5, created_at: 5.minutes.ago)
    create(:applicant_sign_in_code, applicant: applicant, email: email, created_at: 1.minute.ago)

    expect(status.state).to eq(:active)
  end

  it "ignores other addresses and other applicants" do
    create(:applicant_sign_in_code, applicant: applicant, email: "someone.else@example.com")
    create(:applicant_sign_in_code, email: email)

    expect(status.state).to eq(:none)
  end

  it "tolerates the address in another case" do
    create(:applicant_sign_in_code, applicant: applicant, email: email)

    expect(described_class.call(applicant: applicant, email: " Invitee@Example.com ").state).to eq(:active)
  end
end
