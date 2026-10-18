# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormHelper, type: :helper do
  let(:valid_user) { build(:applicant_user).tap(&:valid?) }
  let(:invalid_user) { build(:applicant_user, email: "").tap(&:valid?) }

  describe "#field_class" do
    it "returns the plain input class when the attribute has no errors" do
      expect(helper.field_class(valid_user, :email)).to eq("form-input")
    end

    it "returns the error input class when the attribute has errors" do
      expect(helper.field_class(invalid_user, :email)).to eq("form-input-error")
    end
  end

  describe "#field_error" do
    it "renders nothing when the attribute has no errors" do
      expect(helper.field_error(valid_user, :email)).to be_nil
    end

    it "renders the first error message in a form-error paragraph" do
      html = Capybara.string(helper.field_error(invalid_user, :email))

      expect(html).to have_css("p.form-error", text: invalid_user.errors.full_messages_for(:email).first)
    end
  end

  # MH-395: applicant twins. The error look comes from aria-invalid on the
  # field (kyn-input), so the class never changes; the message sits in a
  # kyn-field wrapper, which restyles it.
  describe "#kyn_field_class" do
    it "returns kyn-input when the attribute has no errors" do
      expect(helper.kyn_field_class(valid_user, :email)).to eq("kyn-input")
    end

    it "returns kyn-input when the attribute has errors, because aria-invalid carries the error look" do
      expect(helper.kyn_field_class(invalid_user, :email)).to eq("kyn-input")
    end
  end

  describe "#kyn_field_aria" do
    it "marks an invalid field and points it at its message" do
      aria = helper.kyn_field_aria(invalid_user, :email, "applicant_user_email-error")

      expect(aria).to eq("aria-invalid": "true", "aria-describedby": "applicant_user_email-error")
    end

    it "adds nothing for a valid field" do
      expect(helper.kyn_field_aria(valid_user, :email, "applicant_user_email-error")).to eq({})
    end
  end

  describe "#kyn_field_error" do
    it "renders nothing when the attribute has no errors" do
      expect(helper.kyn_field_error(valid_user, :email)).to be_nil
    end

    it "renders the first error as an announced form-error paragraph with the given id" do
      html = Capybara.string(helper.kyn_field_error(invalid_user, :email, id: "applicant_user_email-error"))

      expect(html).to have_css(
        "p#applicant_user_email-error.form-error[data-form-validation-error]",
        text: invalid_user.errors.full_messages_for(:email).first
      )
    end
  end
end
