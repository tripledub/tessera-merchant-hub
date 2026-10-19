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
