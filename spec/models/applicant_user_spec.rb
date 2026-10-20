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

  it "belongs to an applicant" do
    expect(applicant_user.applicant).to be_an(Applicant)
  end

  # MH-413: with one-time-code sign-in the first verified invitee is an email
  # address and nothing else.
  describe "a user with only an email" do
    subject(:nameless) { build(:applicant_user, :nameless) }

    it "is valid, and can be saved" do
      expect(nameless).to be_valid
      expect { nameless.save! }.to change(described_class, :count).by(1)
      expect(nameless.reload.first_name).to be_nil
      expect(nameless.encrypted_password).to eq("")
    end

    it "cannot sign in with a password, whatever it tries" do
      nameless.save!

      [ "password123!", "", " ", nameless.email, "x" * 20 ].each do |attempt|
        expect(nameless.valid_password?(attempt)).to be(false)
      end
    end

    it "stays valid when updated without touching a password" do
      nameless.save!

      expect(nameless.update(confirmed_at: Time.current)).to be(true)
    end

    it "can set a password later, and then signs in with it" do
      nameless.save!

      expect(nameless.update(password: "a-long-passphrase", password_confirmation: "a-long-passphrase")).to be(true)
      expect(nameless.reload.valid_password?("a-long-passphrase")).to be(true)
    end

    it "can reset a password through the existing reset flow" do
      nameless.save!

      expect(nameless.reset_password("a-long-passphrase", "a-long-passphrase")).to be(true)
      expect(nameless.reload.valid_password?("a-long-passphrase")).to be(true)
    end
  end

  describe "a password that is set" do
    it "still has to follow the rules" do
      user = build(:applicant_user, :nameless)

      user.password = user.password_confirmation = "short"
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present

      user.password = user.password_confirmation = "x" * 129
      expect(user).not_to be_valid

      user.password = "a-long-passphrase"
      user.password_confirmation = "a different passphrase"
      expect(user).not_to be_valid
      expect(user.errors[:password_confirmation]).to be_present
    end

    it "cannot be set to blank" do
      user = build(:applicant_user, :nameless, password: "", password_confirmation: "")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end
  end

  describe "the password registration form (retired in MH-409) keeps its rules" do
    it "requires a first name, a last name and a password" do
      user = build(:applicant_user, :nameless)

      expect(user.valid?(:password_registration)).to be(false)
      expect(user.errors.attribute_names).to include(:first_name, :last_name, :password)
    end

    it "accepts a user with all three" do
      expect(build(:applicant_user).valid?(:password_registration)).to be(true)
    end

    it "does not report the missing password twice" do
      user = build(:applicant_user, :nameless)
      user.valid?(:password_registration)

      expect(user.errors[:password].size).to eq(1)
    end
  end

  # MH-407: the name is optional, so it only has to be tidy and a sensible length.
  describe "names" do
    it "strips surrounding spaces" do
      user = build(:applicant_user, first_name: "  Alex ", last_name: "\tSample  ")

      expect(user).to have_attributes(first_name: "Alex", last_name: "Sample")
    end

    it "stores a blank name as nil, never an empty string" do
      user = create(:applicant_user, first_name: "   ", last_name: "")

      expect(user.reload).to have_attributes(first_name: nil, last_name: nil)
    end

    it "allows up to 100 characters and no more" do
      expect(build(:applicant_user, first_name: "a" * 100, last_name: "b" * 100)).to be_valid

      user = build(:applicant_user, first_name: "a" * 101, last_name: "b" * 101)
      expect(user).not_to be_valid
      expect(user.errors.attribute_names).to include(:first_name, :last_name)
    end

    it "is never required outside the retired password registration" do
      expect(build(:applicant_user, :nameless)).to be_valid
    end
  end

  # MH-408: passwords are optional, and applicants choose a stronger minimum than the admin users.
  describe "password rules" do
    it "needs at least 8 characters for an applicant, and at most 128" do
      short = build(:applicant_user, password: "abcdefg", password_confirmation: "abcdefg")
      ok = build(:applicant_user, password: "abcdefgh", password_confirmation: "abcdefgh")
      long = build(:applicant_user, password: "a" * 129, password_confirmation: "a" * 129)

      expect(short).not_to be_valid
      expect(short.errors[:password]).to be_present
      expect(ok).to be_valid
      expect(long).not_to be_valid
    end

    it "leaves the admin user's rules alone (6 to 128)" do
      expect(build(:user, password: "abc123", password_confirmation: "abc123")).to be_valid
      expect(User.password_length).to eq(6..128)
    end

    it "lets an existing 6 or 7 character password keep signing in, because the rule only applies when a password is set" do
      user = create(:applicant_user, :nameless)
      user.update_column(:encrypted_password, Devise::Encryptor.digest(described_class, "abc123"))

      expect(user.reload.valid_password?("abc123")).to be(true)
      expect(user.update(first_name: "Alex")).to be(true)
    end
  end

  describe "#password_prompt_due?" do
    let(:user) { create(:applicant_user, :nameless) }

    def start_onboarding(completed: [ "company" ])
      create(:onboarding_application, applicant: user.applicant, current_step: "fulfilment", completed_steps: completed)
    end

    it "is due for a user with no password, not dismissed, who has completed a step" do
      start_onboarding

      expect(user).to be_password_prompt_due
    end

    it "is not due before any step is completed, or with no application" do
      expect(user).not_to be_password_prompt_due

      start_onboarding(completed: [])
      expect(user.reload).not_to be_password_prompt_due
    end

    it "is not due once dismissed, or once a password is set" do
      start_onboarding
      user.touch(:password_prompt_dismissed_at)
      expect(user).not_to be_password_prompt_due

      other = create(:applicant_user)
      create(:onboarding_application, applicant: other.applicant, current_step: "fulfilment", completed_steps: [ "company" ])
      expect(other).not_to be_password_prompt_due
    end
  end

  describe "#password_set?" do
    it "tells a user with a password from one without" do
      expect(build(:applicant_user)).to be_password_set
      expect(build(:applicant_user, :nameless)).not_to be_password_set
    end
  end

  it "leaves existing users with names and passwords exactly as they were" do
    existing = create(:applicant_user, first_name: "Alex", last_name: "Sample")

    expect(existing.reload).to be_valid
    expect(existing.valid_password?("password123!")).to be(true)
  end

  it "does not change the staff user's validation" do
    staff = build(:user, password: nil)

    expect(staff).not_to be_valid
    expect(staff.errors[:password]).to be_present
  end
end
